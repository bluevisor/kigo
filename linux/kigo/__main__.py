"""Kigo's application: one instance per session, toggled over D-Bus."""
import os
import sys
import threading

import gi

gi.require_version("Gtk", "3.0")
from gi.repository import Gio, GLib, Gtk  # noqa: E402

from . import ICON_DIRS, VERSION  # noqa: E402
from .apps import AppIndex, launch  # noqa: E402
from .commands import open_uri, run_command, terminal  # noqa: E402
from .files import FileIndex  # noqa: E402
from .history import History  # noqa: E402
from .hotkey import X11Hotkey  # noqa: E402
from .prefs import Prefs  # noqa: E402
from . import setup  # noqa: E402
from .ui import Launcher, reveal_result  # noqa: E402
from .updater import Updater  # noqa: E402

USAGE = """usage: kigo [--show | --toggle | --settings | --background | --quit | --uninstall | --version]
Kigo opens with Alt+Space; with no option, this shows it."""


class KigoApp(Gtk.Application):
    def __init__(self):
        super().__init__(application_id=setup.APP_ID, flags=Gio.ApplicationFlags.HANDLES_COMMAND_LINE)
        self.window = None

    def do_startup(self):
        Gtk.Application.do_startup(self)
        self.hold()   # stay running with the window hidden
        theme = Gtk.IconTheme.get_default()
        for folder in ICON_DIRS:
            if os.path.exists(os.path.join(folder, "kigo.svg")):
                theme.append_search_path(os.path.abspath(folder))
        # The leaf (kigo) for Kigo's own logo; the tile (com.bluevisor.kigo)
        # where the desktop shows the app.
        for folder in ICON_DIRS:
            if os.path.exists(os.path.join(folder, setup.APP_ID + ".png")):
                theme.append_search_path(os.path.abspath(folder))
        Gtk.Window.set_default_icon_name(setup.APP_ID)
        self.prefs = Prefs()
        self.history = History()
        self.history.load()
        self.apps = AppIndex()
        self.files = FileIndex()
        self.files.refresh_if_stale(0)
        self.window = Launcher(self)
        self.updater = Updater(self)
        for name, handler in (("toggle", lambda *_: self.window.toggle()),
                              ("show", lambda *_: self.window.show_launcher()),
                              ("settings", lambda *_: self.window.show_launcher(settings=True)),
                              ("quit", lambda *_: self.quit())):
            action = Gio.SimpleAction.new(name, None)
            action.connect("activate", handler)
            self.add_action(action)
        self.hotkey = X11Hotkey(self._hotkey_pressed)
        if setup.installed():
            setup.apply_shortcut(self.prefs["shortcut"])
            setup.apply_autostart(self.prefs["autostart"])
            self.updater.start()
        # After GNOME's binding: where its shortcut holds the key this fails
        # and GNOME runs the toggle; elsewhere Kigo listens itself.
        GLib.timeout_add(1500, self._grab_hotkey)

    def do_command_line(self, command_line):
        args = command_line.get_arguments()[1:]
        if "--toggle" in args:
            self.window.toggle()
        elif "--settings" in args:
            self.window.show_launcher(settings=True)
        elif "--quit" in args:
            self.quit()
        elif "--uninstall" in args:
            self.uninstall()
        elif "--background" not in args:
            self.window.show_launcher()
        return 0

    def _hotkey_pressed(self):
        # The grab takes the focus while the key is down, so the panel never
        # looks active here (`toggle` would show it again): showing is enough.
        if self.window.get_visible():
            self.window.hide_launcher()
        else:
            self.window.show_launcher()

    def _grab_hotkey(self):
        """Kigo's own grab; retried for a while on X11, since GNOME lets go
        of a shortcut Kigo just took away a moment later."""
        from .prefs import SHORTCUTS
        self.grab_tries = getattr(self, "grab_tries", 0) + 1
        if self.hotkey.grab(SHORTCUTS[self.prefs["shortcut"]][1]) or not setup.x11() or self.grab_tries >= 10:
            self.grab_tries = 0
            return False
        return True   # GLib calls it again

    def apps_maybe_refresh(self):
        pass   # Gio.AppInfoMonitor rebuilds the index when .desktop files change

    def pref_changed(self, key):
        if key == "shortcut":
            if setup.installed():
                setup.apply_shortcut(self.prefs["shortcut"])
            self.hotkey.release()
            GLib.timeout_add(1500, self._grab_hotkey)
        elif key == "autostart" and setup.installed():
            setup.apply_autostart(self.prefs["autostart"])

    def message(self, title, text):
        dialog = Gtk.MessageDialog(transient_for=self.window if self.window.get_visible() else None,
                                   message_type=Gtk.MessageType.INFO, buttons=Gtk.ButtonsType.OK, text=title)
        dialog.format_secondary_text(text)
        dialog.set_keep_above(True)
        dialog.run()
        dialog.destroy()
        return False

    def invoke(self, result, reveal, alternate, confirming):
        """What Enter does: "hide", "confirm", "settings", "stay" or "failed"."""
        if reveal:
            return "hide" if reveal_result(result) else "failed"
        if result.needs_confirm and confirming != result.id:
            return "confirm"
        if result.kind == "command" and result.payload in ("settings", "reindex", "update", "quit"):
            self.history.record(result.id, result.title)
            if result.payload == "settings":
                return "settings"
            if result.payload == "reindex":
                self.apps.rebuild()
                self.files.refresh_if_stale(0)
            elif result.payload == "update":
                self.updater.check(manual=True)
            else:
                GLib.idle_add(self.quit)
            return "hide"

        if result.kind in ("app", "pref"):
            context = self.window.get_display().get_app_launch_context()
            ok = launch(result, context)
        elif result.kind in ("file", "folder"):
            ok = open_uri(Gio.File.new_for_path(result.path).get_uri())
        elif result.kind in ("url", "web"):
            ok = open_uri(result.payload)
        elif result.kind == "calc":
            clipboard = Gtk.Clipboard.get_default(self.window.get_display())
            clipboard.set_text(result.payload, -1)
            clipboard.store()
            ok = True
        elif result.kind == "shell":
            ok = terminal(result.payload)
        else:
            ok = run_command(result.payload)
        if not ok:
            return "failed"
        if result.kind in ("app", "pref", "file", "folder", "command"):
            self.history.record(result.id, result.title)
        return "hide"

    def uninstall(self):
        setup.remove_shortcut()
        setup.apply_autostart(False)
        share = os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share")
        for path in (setup.WRAPPER, os.path.join(share, "applications", setup.APP_ID + ".desktop"),
                     os.path.join(share, "icons/hicolor/512x512/apps/com.bluevisor.kigo.png")):
            if os.path.exists(path):
                os.remove(path)
        threading.Thread(target=lambda: os.system("rm -rf '%s'" % os.path.join(share, "kigo", "app")),
                         daemon=True).start()
        print("Kigo is uninstalled; your settings stay in ~/.config/kigo.")
        GLib.timeout_add(300, lambda: self.quit() or False)


def main():
    if "--help" in sys.argv or "-h" in sys.argv:
        print(USAGE)
        return 0
    if "--version" in sys.argv:
        print("Kigo", VERSION)
        return 0
    return KigoApp().run(sys.argv)


if __name__ == "__main__":
    sys.exit(main())
