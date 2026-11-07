"""Built-in commands, link detection, and what Enter does for each kind of
result (through desktop tools, so it works on any freedesktop system)."""
import os
import shlex
import shutil
import subprocess

from .fuzzy import fuzzy_score

HOME = os.path.expanduser("~")


def _xdg_dir(name, fallback):
    try:
        out = subprocess.run(["xdg-user-dir", name], capture_output=True, text=True, timeout=2).stdout.strip()
        if out and out != HOME:
            return out
    except (OSError, subprocess.SubprocessError):
        pass
    return os.path.join(HOME, fallback)


# id, title, subtitle, keywords, icon name, needs confirm, folder
COMMANDS = [
    ("sleep", "Sleep", "System", "suspend", "weather-clear-night-symbolic", False, None),
    ("lock", "Lock Screen", "System", "away", "system-lock-screen-symbolic", False, None),
    ("restart", "Restart", "System", "reboot", "system-reboot-symbolic", True, None),
    ("shutdown", "Shut Down", "System", "power off poweroff halt", "system-shutdown-symbolic", True, None),
    ("logout", "Log Out", "System", "sign out signout", "system-log-out-symbolic", True, None),
    ("empty-trash", "Empty Trash", "Files", "delete clean bin", "user-trash-full-symbolic", True, None),
    ("dark-mode", "Toggle Dark Mode", "Appearance", "light theme appearance night",
     "weather-clear-night-symbolic", False, None),
    ("home", "Home", "Folder", "folder user", "user-home", False, "HOME"),
    ("desktop", "Desktop", "Folder", "folder", "user-desktop", False, "DESKTOP"),
    ("documents", "Documents", "Folder", "folder", "folder-documents", False, "DOCUMENTS"),
    ("downloads", "Downloads", "Folder", "folder", "folder-download", False, "DOWNLOAD"),
    ("trash", "Trash", "Folder", "bin deleted", "user-trash", False, "TRASH"),
    ("new-terminal", "New Terminal Window", "Terminal", "shell console", "utilities-terminal", False, None),
    ("settings", "Kigo Settings", "Kigo", "preferences options configure setup", "com.bluevisor.kigo", False, None),
    ("reindex", "Reload Applications", "Kigo", "refresh rescan reindex", "com.bluevisor.kigo", False, None),
    ("update", "Check for Updates", "Kigo", "upgrade update version kigo", "com.bluevisor.kigo", False, None),
    ("quit", "Quit Kigo", "Kigo", "exit close", "com.bluevisor.kigo", False, None),
]

_folders = {}


def folder_path(key):
    if key not in _folders:
        if key == "HOME":
            _folders[key] = HOME
        elif key == "TRASH":
            base = os.environ.get("XDG_DATA_HOME") or os.path.join(HOME, ".local/share")
            _folders[key] = os.path.join(base, "Trash/files")
        else:
            _folders[key] = _xdg_dir(key, key.capitalize() if key != "DOWNLOAD" else "Downloads")
    return _folders[key]


def _make(info):
    from .model import Result
    cid, title, subtitle, _, icon, confirm, folder = info
    result = Result("command", title, "cmd:" + cid, subtitle, cid, icon=("name", icon), needs_confirm=confirm)
    if folder:
        path = folder_path(folder)
        result.kind = "folder"
        result.path = path
        result.subtitle = "~" + path[len(HOME):] if path.startswith(HOME) else path
        result.icon = ("name", icon)
    return result


def search_commands(query, all_commands=True):
    results = []
    for info in COMMANDS:
        if not all_commands and info[0] != "settings":
            continue
        score = fuzzy_score(query, info[1])
        for word in info[3].split():
            keyword = fuzzy_score(query, word) * 0.75
            if keyword >= 600 and keyword > score:
                score = keyword
        if score > 0:
            result = _make(info)
            result.score = score
            results.append(result)
    return results


def command_for_id(key):
    if not key.startswith("cmd:"):
        return None
    for info in COMMANDS:
        if info[0] == key[4:]:
            return _make(info)
    return None


def url_for(text):
    """"apple.com", "github.com/x", "https://…": the URL to open, or None."""
    text = text.strip()
    if not text or " " in text:
        return None
    lower = text.lower()
    if lower.startswith(("http://", "https://", "ftp://", "file://")):
        return text
    if lower.startswith("www."):
        return "https://" + text
    host = text.split("/", 1)[0]
    dot = host.rfind(".")
    if dot <= 0:
        return None
    tld = host[dot + 1:]
    if len(tld) < 2 or not (tld.isascii() and tld.isalpha()):
        return None
    if not all(c.isascii() and (c.isalnum() or c in ".-:") for c in host):
        return None
    return "https://" + text


# Actions ------------------------------------------------------------------

def spawn(argv):
    """Starts a program detached from Kigo; False when it isn't there."""
    if not shutil.which(argv[0]):
        return False
    try:
        subprocess.Popen(argv, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                         stderr=subprocess.DEVNULL, start_new_session=True)
        return True
    except OSError:
        return False


def terminal(command=None):
    """Opens a terminal, running `command` (kept open afterwards) if given."""
    shell = os.environ.get("SHELL", "/bin/bash")
    script = ["%s -c %s; exec %s" % (shell, shlex.quote(command), shell)] if command else None
    if shutil.which("gnome-terminal"):
        return spawn(["gnome-terminal", "--"] + ([shell, "-c", script[0]] if script else []))
    for term in ("x-terminal-emulator", "konsole", "xfce4-terminal", "xterm"):
        if shutil.which(term):
            return spawn([term, "-e", shell, "-c", script[0]] if script else [term])
    return False


def open_uri(uri):
    return spawn(["xdg-open", uri]) or spawn(["gio", "open", uri])


def reveal(path):
    """Shows the file selected in the file manager."""
    uri = "file://" + path
    if spawn(["gdbus", "call", "--session", "--dest", "org.freedesktop.FileManager1",
              "--object-path", "/org/freedesktop/FileManager1",
              "--method", "org.freedesktop.FileManager1.ShowItems", "['%s']" % uri, ""]):
        return True
    return open_uri(os.path.dirname(path))


def toggle_dark_mode():
    try:
        current = subprocess.run(["gsettings", "get", "org.gnome.desktop.interface", "color-scheme"],
                                 capture_output=True, text=True, timeout=2).stdout.strip()
    except (OSError, subprocess.SubprocessError):
        return False
    dark = "dark" in current
    ok = spawn(["gsettings", "set", "org.gnome.desktop.interface", "color-scheme",
                "default" if dark else "prefer-dark"])
    # GTK 3 apps follow the theme name, not the color scheme.
    theme = subprocess.run(["gsettings", "get", "org.gnome.desktop.interface", "gtk-theme"],
                           capture_output=True, text=True).stdout.strip().strip("'")
    if theme:
        base = theme[:-5] if theme.endswith("-dark") else theme
        spawn(["gsettings", "set", "org.gnome.desktop.interface", "gtk-theme", base if dark else base + "-dark"])
    return ok


def run_command(cid):
    """System commands; Kigo's own ones are handled by the app."""
    if cid == "sleep":
        return spawn(["systemctl", "suspend"])
    if cid == "lock":
        return spawn(["loginctl", "lock-session"]) or spawn(["xdg-screensaver", "lock"])
    if cid == "restart":
        return spawn(["gnome-session-quit", "--reboot"]) or spawn(["systemctl", "reboot"])
    if cid == "shutdown":
        return spawn(["gnome-session-quit", "--power-off"]) or spawn(["systemctl", "poweroff"])
    if cid == "logout":
        return spawn(["gnome-session-quit", "--logout", "--no-prompt"])
    if cid == "empty-trash":
        return spawn(["gio", "trash", "--empty"])
    if cid == "dark-mode":
        return toggle_dark_mode()
    if cid == "new-terminal":
        return terminal()
    return False
