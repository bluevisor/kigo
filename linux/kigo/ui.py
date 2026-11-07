"""The launcher window: a rounded charcoal panel with the query field, ranked
results and an action footer, which turns into the settings page in place."""
import threading

import gi

gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
from gi.repository import Gdk, Gio, GLib, Gtk, Pango  # noqa: E402

from . import VERSION  # noqa: E402
from .commands import reveal  # noqa: E402
from .model import build_results, file_result  # noqa: E402
from .prefs import SHORTCUTS, SIZES, THEMES, WEB_SEARCH  # noqa: E402

MARGIN = 24        # room around the panel for its shadow
ICON = 28


def _rgba(hex_color, alpha):
    h = hex_color.lstrip("#")
    return "rgba(%d,%d,%d,%.2f)" % (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), alpha)


def css(dark, theme, scale):
    s = lambda px: "%dpx" % round(px * scale)  # noqa: E731
    fg, dim, faint = ("#f2f2f2", "rgba(242,242,242,0.62)", "rgba(242,242,242,0.40)") if dark else \
        ("#1d1d1f", "rgba(29,29,31,0.62)", "rgba(29,29,31,0.42)")
    line = "rgba(255,255,255,0.10)" if dark else "rgba(0,0,0,0.10)"
    return """
window.kigo { background-color: transparent; }
.panel {
  background-color: %(bg)s; color: %(fg)s;
  border: 1px solid %(border)s; border-radius: %(r)s;
  box-shadow: 0 10px 28px rgba(0,0,0,0.42), 0 0 0 0.5px rgba(0,0,0,0.25);
}
.panel label { color: %(fg)s; }
.panel .dim { color: %(dim)s; }
.panel .faint { color: %(faint)s; }
.header { min-height: %(field)s; padding: 0 %(p14)s 0 %(p16)s; }
entry.query, entry.query:focus {
  background: none; border: none; box-shadow: none; outline: none;
  font-size: %(f21)s; color: %(fg)s; caret-color: %(theme)s; padding: 0; min-height: %(field)s;
}
entry.query selection { background-color: %(theme_soft)s; }
.line { background-color: %(line)s; min-height: 1px; }
list.results, list.results row { background: none; }
list.results { padding: %(p6)s %(p10)s; }
row.result { min-height: %(row)s; padding: 0 %(p12)s; border-radius: %(p10)s; border: 1px solid transparent; }
row.result:selected { background-color: %(theme_soft)s; border-color: %(theme_edge)s; }
row.result:selected label { color: %(fg)s; }
row.result .title { font-size: %(f14)s; }
row.result .subtitle, row.result .kind { font-size: %(f12)s; }
.section { font-size: %(f12)s; font-weight: bold; padding: %(p10)s %(p12)s %(p4)s %(p12)s; }
.section-line { background-color: %(line)s; min-height: 1px; margin: 0 %(p6)s; }
.footer { min-height: %(footer)s; padding: 0 %(p16)s; }
.footer label { font-size: %(f12)s; }
.footer .strong { font-weight: 600; }
.keycap {
  font-size: %(f11)s; font-weight: 600; color: %(dim)s; background-color: %(keycap)s;
  border-radius: %(p5)s; padding: %(p1)s %(p5)s; min-width: %(p12)s;
}
button.flat-icon { background: none; border: none; box-shadow: none; padding: %(p4)s; color: %(dim)s; }
button.flat-icon:hover { color: %(fg)s; }
.settings-title { font-size: %(f18)s; font-weight: bold; }
.settings { padding: 0 %(p16)s %(p16)s %(p16)s; }
.settings-section { font-size: %(f13)s; font-weight: 500; color: %(dim)s; padding: %(p14)s %(p4)s %(p6)s %(p4)s; }
.card { background-color: %(card)s; border: 1px solid %(card_edge)s; border-radius: %(p12)s; padding: 0 %(p14)s; }
.card .row { min-height: %(p52)s; padding: %(p8)s 0; }
.card .row-title { font-size: %(f13)s; font-weight: 500; }
.card .row-subtitle { font-size: %(f11)s; }
.card .row-line { background-color: %(line)s; min-height: 1px; }
.segmented button { padding: %(p2)s %(p10)s; min-height: 0; font-size: %(f12)s; }
.segmented button:checked { background-image: none; background-color: %(theme_soft)s; color: %(fg)s; }
switch:checked { background-color: %(theme)s; border-color: %(theme)s; }
button.swatch { padding: 0; min-width: %(p20)s; min-height: %(p20)s; border-radius: 999px;
  border: 2px solid transparent; box-shadow: none; background-image: none; }
button.swatch.chosen { border-color: %(fg)s; }
""" % dict(
        bg="rgba(28,28,30,0.94)" if dark else "rgba(248,248,248,0.95)",
        border="rgba(255,255,255,0.16)" if dark else "rgba(0,0,0,0.16)",
        fg=fg, dim=dim, faint=faint, line=line, theme=theme,
        theme_soft=_rgba(theme, 0.17), theme_edge=_rgba(theme, 0.42),
        keycap="rgba(255,255,255,0.08)" if dark else "rgba(0,0,0,0.06)",
        card="rgba(255,255,255,0.035)" if dark else "rgba(0,0,0,0.03)",
        card_edge="rgba(255,255,255,0.11)" if dark else "rgba(0,0,0,0.10)",
        r=s(16), field=s(56), row=s(40), footer=s(38),
        f11=s(11), f12=s(12), f13=s(13), f14=s(14), f18=s(18), f21=s(21),
        p1=s(1), p2=s(2), p4=s(4), p5=s(5), p6=s(6), p8=s(8), p10=s(10), p12=s(12), p14=s(14), p16=s(16),
        p20=s(20), p52=s(52),
    )


def keycap(text):
    label = Gtk.Label(label=text)
    label.get_style_context().add_class("keycap")
    label.set_valign(Gtk.Align.CENTER)
    return label


def icon_image(icon, size):
    kind, value = icon if icon else ("name", "application-x-executable")
    image = None
    if kind == "gicon" and value is not None:
        image = Gtk.Image.new_from_gicon(value, Gtk.IconSize.DND)
    elif kind == "path":
        try:
            info = Gio.File.new_for_path(value).query_info("standard::icon", Gio.FileQueryInfoFlags.NONE, None)
            image = Gtk.Image.new_from_gicon(info.get_icon(), Gtk.IconSize.DND)
        except GLib.Error:
            pass
    if image is None:
        image = Gtk.Image.new_from_icon_name(value if kind == "name" else "text-x-generic", Gtk.IconSize.DND)
    image.set_pixel_size(size)
    return image


class ResultRow(Gtk.ListBoxRow):
    def __init__(self, result, scale):
        super().__init__()
        self.result = result
        self.get_style_context().add_class("result")
        box = Gtk.Box(spacing=round(12 * scale))
        box.pack_start(icon_image(result.icon, round(ICON * scale)), False, False, 0)
        title = Gtk.Label(label=result.title, xalign=0)
        title.get_style_context().add_class("title")
        title.set_ellipsize(Pango.EllipsizeMode.END)
        box.pack_start(title, False, False, 0)
        if result.subtitle:
            subtitle = Gtk.Label(label=result.subtitle, xalign=0)
            subtitle.get_style_context().add_class("subtitle")
            subtitle.get_style_context().add_class("dim")
            subtitle.set_ellipsize(Pango.EllipsizeMode.MIDDLE)
            box.pack_start(subtitle, True, True, 0)
        self.trailing = Gtk.Label(label=result.label)
        self.trailing.get_style_context().add_class("kind")
        self.trailing.get_style_context().add_class("faint")
        box.pack_end(self.trailing, False, False, 0)
        self.add(box)

    def set_state(self, selected, confirming):
        if confirming:
            self.trailing.set_text("Press ↩ again to %s" % self.result.title.lower())
        else:
            self.trailing.set_text("↩" if selected else self.result.label)


class Launcher(Gtk.Window):
    def __init__(self, app):
        super().__init__(application=app, title="Kigo")
        self.app = app
        self.prefs = app.prefs
        self.results = []
        self.file_hits = []
        self.confirming = None
        self.suggestions_hidden = False
        self.search_serial = 0
        self.settings_open = False
        self.shown_at = 0

        self.set_decorated(False)
        self.set_resizable(False)
        self.set_keep_above(True)
        self.set_skip_taskbar_hint(True)
        self.set_skip_pager_hint(True)
        self.set_type_hint(Gdk.WindowTypeHint.DIALOG)
        self.set_icon_name("kigo")
        self.get_style_context().add_class("kigo")
        screen = self.get_screen()
        visual = screen.get_rgba_visual()
        if visual is not None and screen.is_composited():
            self.set_visual(visual)
            self.set_app_paintable(True)

        self.provider = Gtk.CssProvider()
        Gtk.StyleContext.add_provider_for_screen(screen, self.provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
        self.interface = Gio.Settings.new("org.gnome.desktop.interface") if _has_schema(
            "org.gnome.desktop.interface") else None
        if self.interface is not None:
            self.interface.connect("changed", lambda *_: self.apply_style())

        self.connect("key-press-event", self.on_key)
        self.connect("focus-out-event", self.on_focus_out)
        self.connect("delete-event", lambda *_: self.hide_launcher() or True)
        self.build()
        self.apply_style()

    # Building ------------------------------------------------------------

    def build(self):
        for child in self.get_children():
            self.remove(child)
        scale = self.prefs.scale
        self.panel = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        self.panel.get_style_context().add_class("panel")
        self.panel.set_margin_start(MARGIN)
        self.panel.set_margin_end(MARGIN)
        self.panel.set_margin_top(MARGIN // 2)
        self.panel.set_margin_bottom(MARGIN + 8)
        self.panel.set_size_request(round(680 * scale), -1)
        self.add(self.panel)

        self.stack = Gtk.Stack()
        self.stack.set_transition_type(Gtk.StackTransitionType.NONE)
        self.stack.set_vhomogeneous(False)
        self.stack.set_hhomogeneous(False)
        self.panel.pack_start(self.stack, True, True, 0)
        self.stack.add_named(self.build_search(scale), "search")
        self.stack.add_named(self.build_settings(scale), "settings")
        self.panel.show_all()

    def _line(self):
        line = Gtk.Box()
        line.get_style_context().add_class("line")
        return line

    def build_search(self, scale):
        page = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        header = Gtk.Box(spacing=round(12 * scale))
        header.get_style_context().add_class("header")
        magnifier = Gtk.Image.new_from_icon_name("system-search-symbolic", Gtk.IconSize.LARGE_TOOLBAR)
        magnifier.set_pixel_size(round(20 * scale))
        magnifier.get_style_context().add_class("dim")
        header.pack_start(magnifier, False, False, 0)
        self.entry = Gtk.Entry()
        self.entry.get_style_context().add_class("query")
        self.entry.set_has_frame(False)
        self.entry.set_placeholder_text("Search apps, files, and commands")
        self.entry.connect("changed", self.on_query_changed)
        header.pack_start(self.entry, True, True, 0)
        gear = Gtk.Button.new_from_icon_name("emblem-system-symbolic", Gtk.IconSize.BUTTON)
        gear.get_style_context().add_class("flat-icon")
        gear.set_relief(Gtk.ReliefStyle.NONE)
        gear.set_tooltip_text("Settings (Alt+,)")
        gear.set_can_focus(False)
        gear.connect("clicked", lambda *_: self.open_settings())
        header.pack_start(gear, False, False, 0)
        header.pack_start(keycap("Alt+,"), False, False, 0)
        page.pack_start(header, False, False, 0)

        self.body = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        self.body.pack_start(self._line(), False, False, 0)
        self.scroller = Gtk.ScrolledWindow()
        # No scroll bars: the panel grows to fit, down to the screen's bottom.
        self.scroller.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.EXTERNAL)
        self.scroller.set_propagate_natural_height(True)
        self.list = Gtk.ListBox()
        self.list.get_style_context().add_class("results")
        self.list.set_selection_mode(Gtk.SelectionMode.SINGLE)
        self.list.set_activate_on_single_click(True)
        self.list.set_header_func(self.list_header)
        self.list.connect("row-activated", lambda _l, row: self.invoke(row.get_index(), False, False))
        self.list.connect("row-selected", lambda *_: self.selection_changed())
        self.list.set_can_focus(False)
        self.scroller.add(self.list)
        self.body.pack_start(self.scroller, True, True, 0)
        self.body.pack_start(self._line(), False, False, 0)
        self.footer_box = Gtk.Box(spacing=round(8 * scale))
        self.footer_box.get_style_context().add_class("footer")
        self.body.pack_start(self.footer_box, False, False, 0)
        page.pack_start(self.body, True, True, 0)
        return page

    def list_header(self, row, before):
        if before is not None and before.result.section == row.result.section:
            row.set_header(None)
            return
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        if before is not None:
            line = Gtk.Box()
            line.get_style_context().add_class("section-line")
            box.pack_start(line, False, False, 0)
        label = Gtk.Label(label=row.result.section, xalign=0)
        label.get_style_context().add_class("section")
        label.get_style_context().add_class("dim")
        box.pack_start(label, False, False, 0)
        box.show_all()
        row.set_header(box)

    def footer(self, settings=False):
        scale = self.prefs.scale
        box = self.footer_box if not settings else self.settings_footer
        for child in box.get_children():
            box.remove(child)
        leaf = Gtk.Image.new_from_icon_name("kigo", Gtk.IconSize.LARGE_TOOLBAR)
        leaf.set_pixel_size(round(20 * scale))
        box.pack_start(leaf, False, False, 0)
        name = Gtk.Label(label="Kigo")
        name.get_style_context().add_class("dim")
        box.pack_start(name, False, False, 0)

        def hint(key, text, strong=False):
            label = Gtk.Label(label=text)
            label.get_style_context().add_class("strong" if strong else "dim")
            box.pack_end(label, False, False, 0)
            box.pack_end(keycap(key), False, False, 0)

        if settings:
            hint("Esc", "Back", True)
        else:
            result = self.selected()
            if result is not None:
                hint("↩", "Confirm" if self.confirming == result.id else result.primary_action, True)
                if result.path:
                    separator = Gtk.Label(label="|")
                    separator.get_style_context().add_class("faint")
                    box.pack_end(separator, False, False, 6)
                    hint("Alt+↩", "Show in Files")
        box.show_all()

    # Settings page -------------------------------------------------------

    def build_settings(self, scale):
        page = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        header = Gtk.Box(spacing=round(10 * scale))
        header.get_style_context().add_class("header")
        back = Gtk.Button.new_from_icon_name("go-previous-symbolic", Gtk.IconSize.BUTTON)
        back.get_style_context().add_class("flat-icon")
        back.set_relief(Gtk.ReliefStyle.NONE)
        back.set_can_focus(False)
        back.connect("clicked", lambda *_: self.close_settings())
        header.pack_start(back, False, False, 0)
        leaf = Gtk.Image.new_from_icon_name("kigo", Gtk.IconSize.DND)
        leaf.set_pixel_size(round(26 * scale))
        header.pack_start(leaf, False, False, 0)
        title = Gtk.Label(label="Kigo Settings")
        title.get_style_context().add_class("settings-title")
        header.pack_start(title, False, False, 0)
        page.pack_start(header, False, False, 0)
        page.pack_start(self._line(), False, False, 0)

        self.settings_scroller = Gtk.ScrolledWindow()
        self.settings_scroller.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.EXTERNAL)
        self.settings_scroller.set_propagate_natural_height(True)
        content = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        content.get_style_context().add_class("settings")
        self.settings_scroller.add(content)
        page.pack_start(self.settings_scroller, True, True, 0)

        p = self.prefs
        self._section(content, "Search", [
            self._switch("Applications", "Apps and Settings panels", "search_apps"),
            self._switch("Files and folders", "Names in your home folder", "search_files"),
            self._switch("Commands", "Sleep, Lock Screen, Empty Trash, folders and more", "search_commands"),
            self._switch("Calculator", "Answers arithmetic as you type", "calculator"),
            self._row("Web search", "Offered last, for anything else", self._segmented("web_search", WEB_SEARCH)),
        ])
        clear = Gtk.Button(label="Clear")
        clear.set_can_focus(False)
        clear.connect("clicked", self.on_clear_history)
        self._section(content, "Suggestions", [
            self._switch("Suggest what you use most", "Shown before you type anything", "suggestions"),
            self._row("Search history", "Forget what you opened; ranking starts over", clear),
        ])
        swatches = Gtk.Box(spacing=round(8 * scale))
        for index, (name, color) in enumerate(THEMES):
            swatch = Gtk.Button()
            swatch.get_style_context().add_class("swatch")
            if index == p["theme"]:
                swatch.get_style_context().add_class("chosen")
            swatch.set_tooltip_text(name)
            swatch.set_can_focus(False)
            provider = Gtk.CssProvider()
            provider.load_from_data(("button { background-color: %s; }" % color).encode())
            swatch.get_style_context().add_provider(provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION + 1)
            swatch.connect("clicked", lambda _b, i=index: self.set_pref("theme", i, rebuild=True))
            swatches.pack_start(swatch, False, False, 0)
        self._section(content, "Appearance", [
            self._row("Theme color", THEMES[p["theme"]][0], swatches),
            self._row("Size", "Text and rows", self._segmented("size", [n for n, _ in SIZES], rebuild=True)),
        ])
        quit_button = Gtk.Button(label="Quit Kigo")
        quit_button.set_can_focus(False)
        quit_button.connect("clicked", lambda *_: self.app.quit())
        update_button = Gtk.Button(label="Check for Updates")
        update_button.set_can_focus(False)
        update_button.connect("clicked", lambda *_: self.app.updater.check(manual=True))
        buttons = Gtk.Box(spacing=8)
        buttons.pack_start(update_button, False, False, 0)
        buttons.pack_start(quit_button, False, False, 0)
        self._section(content, "General", [
            self._row("Shortcut", "Opens Kigo from anywhere",
                      self._segmented("shortcut", [n for n, _ in SHORTCUTS])),
            self._switch("Open at login", "Starts Kigo, hidden, when you log in", "autostart"),
            self._switch("Update automatically", "Installs new versions from GitHub once a day", "updates"),
            self._row("Kigo %s" % VERSION, "Settings: Alt+, or Ctrl+,", buttons),
        ])

        page.pack_start(self._line(), False, False, 0)
        self.settings_footer = Gtk.Box(spacing=round(8 * scale))
        self.settings_footer.get_style_context().add_class("footer")
        page.pack_start(self.settings_footer, False, False, 0)
        self.footer(settings=True)
        return page

    def _section(self, parent, title, rows):
        label = Gtk.Label(label=title, xalign=0)
        label.get_style_context().add_class("settings-section")
        parent.pack_start(label, False, False, 0)
        card = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        card.get_style_context().add_class("card")
        for i, row in enumerate(rows):
            if i:
                line = Gtk.Box()
                line.get_style_context().add_class("row-line")
                card.pack_start(line, False, False, 0)
            card.pack_start(row, False, False, 0)
        parent.pack_start(card, False, False, 0)

    def _row(self, title, subtitle, control):
        row = Gtk.Box(spacing=12)
        row.get_style_context().add_class("row")
        text = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        text.set_valign(Gtk.Align.CENTER)
        t = Gtk.Label(label=title, xalign=0)
        t.get_style_context().add_class("row-title")
        s = Gtk.Label(label=subtitle, xalign=0)
        s.get_style_context().add_class("row-subtitle")
        s.get_style_context().add_class("dim")
        text.pack_start(t, False, False, 0)
        text.pack_start(s, False, False, 0)
        row.pack_start(text, True, True, 0)
        control.set_valign(Gtk.Align.CENTER)
        row.pack_end(control, False, False, 0)
        return row

    def _switch(self, title, subtitle, key):
        switch = Gtk.Switch()
        switch.set_active(bool(self.prefs[key]))
        switch.set_can_focus(False)
        switch.connect("notify::active", lambda w, _p: self.set_pref(key, w.get_active()))
        return self._row(title, subtitle, switch)

    def _segmented(self, key, names, rebuild=False):
        box = Gtk.Box()
        box.get_style_context().add_class("linked")
        box.get_style_context().add_class("segmented")
        group = None
        for index, name in enumerate(names):
            button = Gtk.RadioButton.new_with_label_from_widget(group, name)
            button.set_mode(False)   # draw as a toggle button, not a radio dot
            button.set_can_focus(False)
            group = group or button
            button.set_active(index == self.prefs[key])
            button.connect("toggled", lambda b, i=index: b.get_active() and self.set_pref(key, i, rebuild=rebuild))
            box.pack_start(button, False, False, 0)
        return box

    def set_pref(self, key, value, rebuild=False):
        if self.prefs[key] == value:
            return
        self.prefs.set(key, value)
        self.app.pref_changed(key)
        if rebuild:
            # Sizes and colors are baked into the widgets: build them again.
            GLib.idle_add(self._rebuild_settings)
        else:
            self.update(keep=True)

    def _rebuild_settings(self):
        self.build()
        self.apply_style()
        self.stack.set_visible_child_name("settings")
        self.relayout()
        return False

    def on_clear_history(self, button):
        self.app.history.clear()
        button.set_label("Cleared")
        button.set_sensitive(False)
        self.update()

    # Style and size -------------------------------------------------------

    def is_dark(self):
        if self.interface is not None:
            keys = self.interface.props.settings_schema.list_keys()
            if "color-scheme" in keys and self.interface.get_string("color-scheme") == "prefer-dark":
                return True
            return self.interface.get_string("gtk-theme").lower().endswith("-dark")
        return True

    def apply_style(self):
        dark = self.is_dark()
        Gtk.Settings.get_default().props.gtk_application_prefer_dark_theme = dark
        self.provider.load_from_data(css(dark, self.prefs.theme_color, self.prefs.scale).encode())

    def room(self):
        """How tall the list or settings may grow before the screen's bottom."""
        if not hasattr(self, "workarea"):
            return 600
        top = self.workarea.y + self.workarea.height * 0.18
        bottom = self.workarea.y + self.workarea.height - 24
        scale = self.prefs.scale
        return max(160, int(bottom - top - (56 + 38 + 2) * scale - MARGIN))

    def relayout(self):
        room = self.room()
        self.scroller.set_max_content_height(room)
        self.settings_scroller.set_max_content_height(room)
        self.settings_scroller.set_min_content_height(min(room, 600))
        # A non-resizable window takes its natural size; ask for the smallest.
        self.resize(1, 1)

    # Showing ---------------------------------------------------------------

    def place(self):
        display = Gdk.Display.get_default()
        seat = display.get_default_seat()
        _, x, y = seat.get_pointer().get_position()
        monitor = display.get_monitor_at_point(x, y) or display.get_primary_monitor() or display.get_monitor(0)
        self.workarea = monitor.get_workarea()
        width = round(680 * self.prefs.scale) + 2 * MARGIN
        self.move(self.workarea.x + (self.workarea.width - width) // 2,
                  int(self.workarea.y + self.workarea.height * 0.18) - MARGIN // 2)

    def show_launcher(self, settings=False):
        if not self.get_visible():
            self.entry.set_text("")
            self.confirming = None
            self.suggestions_hidden = False
            self.settings_open = False
            self.stack.set_visible_child_name("search")
            self.app.apps_maybe_refresh()
            self.app.files.refresh_if_stale()
            self.place()
            self.update()
        if settings:
            self.open_settings()
        self.show()
        self.relayout()
        self.shown_at = GLib.get_monotonic_time()
        gdk_window = self.get_window()
        timestamp = Gtk.get_current_event_time()
        try:
            gi.require_version("GdkX11", "3.0")
            from gi.repository import GdkX11
            if isinstance(gdk_window, GdkX11.X11Window):
                # Activated over D-Bus there's no event time; the server's lets
                # the window manager give us focus.
                timestamp = GdkX11.x11_get_server_time(gdk_window)
        except (ImportError, ValueError):
            pass
        self.present_with_time(timestamp)
        if not self.settings_open:
            self.entry.grab_focus()

    def hide_launcher(self):
        self.hide()
        self.settings_open = False
        self.confirming = None

    def toggle(self):
        if self.get_visible() and self.is_active():
            self.hide_launcher()
        else:
            self.show_launcher()

    def on_focus_out(self, *_):
        # Click elsewhere and it goes away, like Spotlight (not in the moment
        # it appears, while the window manager hands focus over).
        if GLib.get_monotonic_time() - self.shown_at > 400_000:
            GLib.timeout_add(80, lambda: (not self.is_active() and self.hide_launcher()) and False)
        return False

    def open_settings(self):
        self.settings_open = True
        self.stack.set_visible_child_name("settings")
        self.relayout()

    def close_settings(self):
        self.settings_open = False
        self.stack.set_visible_child_name("search")
        self.update(keep=True)
        self.entry.grab_focus()

    # Results ---------------------------------------------------------------

    def query(self):
        return self.entry.get_text()

    def on_query_changed(self, *_):
        self.confirming = None
        self.file_hits = []
        text = self.query()
        if text:
            self.suggestions_hidden = False
        self.update()
        if self.prefs["search_files"] and len(text.strip()) >= 2 and not text.startswith(">"):
            self.search_serial += 1
            serial = self.search_serial
            # Wait for a pause in typing, then search off the main thread.
            GLib.timeout_add(110, lambda: self._start_file_search(serial, text) and False)

    def _start_file_search(self, serial, text):
        if serial != self.search_serial:
            return False

        def work():
            hits = self.app.files.search(text)
            GLib.idle_add(self._files_arrived, serial, hits)
        threading.Thread(target=work, daemon=True).start()
        return False

    def _files_arrived(self, serial, hits):
        if serial == self.search_serial:
            self.file_hits = [file_result(path, score) for score, path in hits]
            self.update(keep=True)
        return False

    def selected(self):
        row = self.list.get_selected_row()
        return row.result if row is not None else None

    def update(self, keep=False):
        previous = self.selected() if keep else None
        keep_id = previous.id if previous is not None and self.list.get_selected_row().get_index() > 0 else None
        if self.suggestions_hidden and not self.query():
            results = []
        else:
            results = build_results(self.query(), self.prefs, self.app.history, self.app.apps, self.file_hits)
        self.results = results
        for child in self.list.get_children():
            self.list.remove(child)
        scale = self.prefs.scale
        for result in results:
            self.list.add(ResultRow(result, scale))
        self.list.show_all()
        index = next((i for i, r in enumerate(results) if r.id == keep_id), 0)
        if results:
            self.list.select_row(self.list.get_row_at_index(index))
        self.body.set_visible(bool(results))
        self.selection_changed()
        self.relayout()

    def selection_changed(self):
        selected = self.list.get_selected_row()
        for row in self.list.get_children():
            row.set_state(row is selected, self.confirming == row.result.id)
        self.footer()

    def move_selection(self, delta):
        if self.results:
            row = self.list.get_selected_row()
            index = max(0, min(len(self.results) - 1, (row.get_index() if row else 0) + delta))
            target = self.list.get_row_at_index(index)
            self.list.select_row(target)
            self.confirming = None
            self.selection_changed()
            # Keep the selection in view.
            adjustment = self.scroller.get_vadjustment()
            allocation = target.get_allocation()
            if allocation.y < adjustment.get_value():
                adjustment.set_value(allocation.y)
            elif allocation.y + allocation.height > adjustment.get_value() + adjustment.get_page_size():
                adjustment.set_value(allocation.y + allocation.height - adjustment.get_page_size())

    def invoke(self, index, reveal_it, alternate):
        if not (0 <= index < len(self.results)):
            return
        outcome = self.app.invoke(self.results[index], reveal_it, alternate, self.confirming)
        if outcome == "confirm":
            self.list.select_row(self.list.get_row_at_index(index))
            self.confirming = self.results[index].id
            self.selection_changed()
        elif outcome == "settings":
            self.entry.set_text("")
            self.open_settings()
        elif outcome == "hide":
            self.hide_launcher()
        elif outcome == "failed":
            self.get_display().beep()

    # Keys -----------------------------------------------------------------

    def on_key(self, _widget, event):
        key = Gdk.keyval_name(event.keyval) or ""
        state = event.state & Gtk.accelerator_get_default_mod_mask()
        alt = bool(state & Gdk.ModifierType.MOD1_MASK)
        ctrl = bool(state & Gdk.ModifierType.CONTROL_MASK)
        shift = bool(state & Gdk.ModifierType.SHIFT_MASK)

        if key == "comma" and (alt or ctrl):
            self.close_settings() if self.settings_open else self.open_settings()
            return True
        if self.settings_open:
            if key in ("Escape", "BackSpace"):
                self.close_settings()
                return True
            return False

        row = self.list.get_selected_row()
        index = row.get_index() if row else 0
        if key == "Up":
            self.move_selection(-1)
        elif key == "Down":
            if not self.query() and self.suggestions_hidden:
                self.suggestions_hidden = False
                self.update()
            else:
                self.move_selection(1)
        elif key in ("Page_Up", "Page_Down"):
            self.move_selection(-5 if key == "Page_Up" else 5)
        elif key in ("Return", "KP_Enter"):
            self.invoke(index, alt or ctrl, shift)
        elif key == "Escape":
            if self.query():
                self.entry.set_text("")
            else:
                self.hide_launcher()
        elif key == "Tab" and not shift:
            result = self.selected()
            if result is not None and result.kind not in ("calc", "web", "shell", "url"):
                self.entry.set_text(result.title)
                self.entry.set_position(-1)
        elif key == "BackSpace" and not self.query() and self.results and not (alt or ctrl):
            # Nothing typed: put the suggestions away, back to the bare search bar.
            self.suggestions_hidden = True
            self.update()
        elif ctrl and not alt and key in ("n", "p"):
            self.move_selection(1 if key == "n" else -1)
        elif (alt or ctrl) and shift and key in ("c", "C"):
            result = self.selected()
            text = result and (result.path or (result.payload if result.kind in ("calc", "url", "web", "shell") else None))
            if text:
                Gtk.Clipboard.get(Gdk.SELECTION_CLIPBOARD).set_text(text, -1)
                Gtk.Clipboard.get(Gdk.SELECTION_CLIPBOARD).store()
                self.hide_launcher()
            else:
                self.get_display().beep()
        elif alt and key.isdigit() and key != "0":
            self.invoke(int(key) - 1, False, False)
        elif ctrl and key == "w":
            self.hide_launcher()
        else:
            return False
        return True


def _has_schema(name):
    source = Gio.SettingsSchemaSource.get_default()
    return source is not None and source.lookup(name, True) is not None


def reveal_result(result):
    return bool(result.path) and reveal(result.path)
