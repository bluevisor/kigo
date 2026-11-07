"""What you picked in Kigo's settings page, kept in ~/.config/kigo/settings.json."""
import json
import os

WEB_SEARCH = ["Off", "DuckDuckGo", "Google", "Bing"]
SIZES = [("Small", 0.88), ("Default", 1.0), ("Large", 1.15), ("Larger", 1.3)]
SHORTCUTS = [("Alt+Space", "<Alt>space"), ("Ctrl+Space", "<Primary>space"), ("Super+Space", "<Super>space")]
THEMES = [
    ("Ginkgo", "#dbad4d"), ("Blue", "#0a84ff"), ("Purple", "#a95cdb"), ("Pink", "#f7549e"),
    ("Red", "#ff4a40"), ("Orange", "#ff9400"), ("Green", "#38c25c"), ("Graphite", "#9999a1"),
]

DEFAULTS = {
    "search_apps": True, "search_files": True, "search_commands": True, "calculator": True,
    "suggestions": True, "web_search": 1, "size": 1, "shortcut": 0, "theme": 0,
    "autostart": True, "updates": True,
}


def config_dir():
    base = os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config")
    path = os.path.join(base, "kigo")
    os.makedirs(path, exist_ok=True)
    return path


class Prefs:
    def __init__(self, path=None):
        self.path = path or os.path.join(config_dir(), "settings.json")
        self.values = dict(DEFAULTS)
        try:
            with open(self.path, encoding="utf-8") as f:
                stored = json.load(f)
            self.values.update({k: v for k, v in stored.items() if k in DEFAULTS})
        except (OSError, ValueError):
            pass

    def __getitem__(self, key):
        return self.values[key]

    def set(self, key, value):
        self.values[key] = value
        temp = self.path + ".new"
        with open(temp, "w", encoding="utf-8") as f:
            json.dump(self.values, f, indent=1)
        os.replace(temp, self.path)

    @property
    def scale(self):
        return SIZES[self["size"]][1]

    @property
    def theme_color(self):
        return THEMES[self["theme"]][1]

    def web_search_url(self, query):
        from urllib.parse import quote_plus
        q = quote_plus(query)
        return {
            1: "https://duckduckgo.com/?q=" + q,
            2: "https://www.google.com/search?q=" + q,
            3: "https://www.bing.com/search?q=" + q,
        }.get(self["web_search"])
