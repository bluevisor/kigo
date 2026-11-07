"""Fitting Kigo into the desktop: the GNOME shortcut that opens it, and the
autostart entry. Applied from settings, so they always match them."""
import os

from gi.repository import Gio

from .prefs import SHORTCUTS, config_dir

APP_ID = "com.bluevisor.kigo"
KEY_PATH = "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/kigo/"
MEDIA_KEYS = "org.gnome.settings-daemon.plugins.media-keys"
WRAPPER = os.path.expanduser("~/.local/bin/kigo")
# GNOME bindings Kigo's shortcuts would collide with: (schema, key, accelerator).
CONFLICTS = [
    ("org.gnome.desktop.wm.keybindings", "activate-window-menu", "<Alt>space"),
    ("org.gnome.desktop.wm.keybindings", "switch-input-source", "<Super>space"),
]


def installed():
    here = os.path.realpath(os.path.dirname(__file__))
    share = os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share")
    return here.startswith(os.path.realpath(os.path.join(share, "kigo", "app")))


def _schema(name):
    source = Gio.SettingsSchemaSource.get_default()
    return source is not None and source.lookup(name, True) is not None


def toggle_command():
    # gdbus answers in milliseconds; starting Python for a second instance doesn't.
    return ("sh -c 'gdbus call --session --dest %s --object-path /com/bluevisor/kigo "
            "--method org.gtk.Actions.Activate toggle [] {} >/dev/null 2>&1 || \"%s\"'" % (APP_ID, WRAPPER))


def apply_shortcut(index):
    """Binds the chosen shortcut to Kigo in GNOME; False on other desktops."""
    if not _schema(MEDIA_KEYS):
        return False
    accel = SHORTCUTS[index][1]
    media = Gio.Settings.new(MEDIA_KEYS)
    paths = media.get_strv("custom-keybindings")
    if KEY_PATH not in paths:
        media.set_strv("custom-keybindings", paths + [KEY_PATH])
    binding = Gio.Settings.new_with_path(MEDIA_KEYS + ".custom-keybinding", KEY_PATH)
    binding.set_string("name", "Kigo")
    binding.set_string("command", toggle_command())
    binding.set_string("binding", accel)
    _free(accel)
    Gio.Settings.sync()
    return True


def _saved_path(key):
    return os.path.join(config_dir(), "saved-" + key)


def _free(accel):
    """Takes `accel` off the GNOME binding it collides with, remembering the
    old value; gives back the ones Kigo no longer uses."""
    for schema, key, conflict in CONFLICTS:
        if not _schema(schema):
            continue
        settings = Gio.Settings.new(schema)
        values = settings.get_strv(key)
        saved = _saved_path(key)
        if conflict == accel and accel in values:
            if not os.path.exists(saved):
                with open(saved, "w") as f:
                    f.write("\n".join(values))
            settings.set_strv(key, [v for v in values if v != accel])
        elif conflict != accel and os.path.exists(saved):
            with open(saved) as f:
                settings.set_strv(key, [v for v in f.read().split("\n") if v])
            os.remove(saved)


def remove_shortcut():
    if not _schema(MEDIA_KEYS):
        return
    media = Gio.Settings.new(MEDIA_KEYS)
    media.set_strv("custom-keybindings", [p for p in media.get_strv("custom-keybindings") if p != KEY_PATH])
    Gio.Settings.new_with_path(MEDIA_KEYS + ".custom-keybinding", KEY_PATH).reset("binding")
    _free(None)
    Gio.Settings.sync()


def _autostart_file():
    base = os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config")
    return os.path.join(base, "autostart", APP_ID + ".desktop")


def apply_autostart(on):
    path = _autostart_file()
    if not on:
        if os.path.exists(path):
            os.remove(path)
        return
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        f.write("[Desktop Entry]\nType=Application\nName=Kigo\nComment=Launcher (Alt+Space)\n"
                "Exec=%s --background\nIcon=kigo\nX-GNOME-Autostart-enabled=true\nNoDisplay=true\n" % WRAPPER)
