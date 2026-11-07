"""The applications (from .desktop files) and settings panels Kigo can open."""
import os
import shutil
import threading

from gi.repository import Gio, GLib

from .fuzzy import fuzzy_score
from .model import Result

# GNOME Settings panels worth finding, with the words people use.
PANELS = [
    ("wifi", "Wi-Fi", "wireless network internet"),
    ("network", "Network", "ethernet vpn proxy internet"),
    ("bluetooth", "Bluetooth", "devices headphones"),
    ("background", "Background", "wallpaper desktop picture"),
    ("ubuntu", "Appearance", "dark mode light theme dock"),
    ("notifications", "Notifications", "alerts banners do not disturb"),
    ("search", "Search", ""),
    ("applications", "Applications", "permissions"),
    ("privacy", "Privacy", "screen lock location"),
    ("online-accounts", "Online Accounts", "google email"),
    ("sharing", "Sharing", "remote desktop ssh screen"),
    ("sound", "Sound", "volume audio output input"),
    ("power", "Power", "battery energy sleep"),
    ("display", "Displays", "monitor resolution night light"),
    ("mouse", "Mouse & Touchpad", "pointer scroll trackpad"),
    ("keyboard", "Keyboard", "shortcuts input sources"),
    ("printers", "Printers", "printer"),
    ("removable-media", "Removable Media", "usb"),
    ("color", "Color", "calibration"),
    ("region", "Region & Language", "locale"),
    ("universal-access", "Accessibility", "zoom screen reader"),
    ("user-accounts", "Users", "accounts password"),
    ("default-apps", "Default Applications", "browser mail"),
    ("datetime", "Date & Time", "clock timezone"),
    ("info-overview", "About", "version system"),
]


class AppIndex:
    def __init__(self):
        self.entries = []   # (name, keywords, app_info or None, panel id or None)
        self.lock = threading.Lock()
        self.monitor = Gio.AppInfoMonitor.get()
        self.monitor.connect("changed", lambda *_: self.rebuild())
        self.has_panels = shutil.which("gnome-control-center") is not None
        self.rebuild()

    def rebuild(self):
        entries = []
        seen = set()
        for info in Gio.AppInfo.get_all():
            if not info.should_show() or info.get_id() in seen:
                continue
            seen.add(info.get_id())
            keywords = []
            if isinstance(info, Gio.DesktopAppInfo):
                keywords += [k.lower() for k in (info.get_keywords() or [])]
                generic = info.get_generic_name()
                if generic:
                    keywords += generic.lower().split()
            executable = os.path.basename(info.get_executable() or "")
            if executable:
                keywords.append(executable)
            entries.append((info.get_display_name() or info.get_name(), keywords, info, None))
        if self.has_panels:
            for panel, name, words in PANELS:
                entries.append((name, words.split(), None, panel))
        with self.lock:
            self.entries = entries

    @staticmethod
    def make_result(entry):
        name, _, info, panel = entry
        if panel:
            return Result("pref", name, "pref:" + panel, "Settings", panel,
                          icon=("name", "org.gnome.Settings"))
        return Result("app", name, "app:" + info.get_id(), info.get_description() or "",
                      payload=info.get_id(), icon=("gicon", info.get_icon()))

    def search(self, query, include=True):
        if not include:
            return []
        with self.lock:
            entries = list(self.entries)
        results = []
        for entry in entries:
            score = fuzzy_score(query, entry[0])
            if score <= 0:
                # Match single keywords so "web" finds browsers; whole-word
                # prefixes only, so short queries don't light up everything.
                for word in entry[1]:
                    keyword = fuzzy_score(query, word)
                    if keyword >= 800 and keyword * 0.7 > score:
                        score = keyword * 0.7
            if score <= 0:
                continue
            result = self.make_result(entry)
            # Apps outrank settings panels at equal match quality.
            result.score = score + (30 if entry[3] else 40)
            results.append(result)
        return results

    def find(self, key):
        with self.lock:
            for entry in self.entries:
                if (entry[2] and key == "app:" + entry[2].get_id()) or (entry[3] and key == "pref:" + entry[3]):
                    return self.make_result(entry)
        return None


def launch(result, launch_context=None):
    if result.kind == "pref":
        from .commands import spawn
        return spawn(["gnome-control-center", result.payload])
    info = Gio.DesktopAppInfo.new(result.payload)
    if info is None:
        return False
    try:
        return info.launch([], launch_context)
    except GLib.Error:
        return False
