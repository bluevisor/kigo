"""What the launcher shows: results for a query, ranked across kinds, with a
Top Hit, history boosts and the web/shell fallbacks. No GTK in here."""
import os

from .calculator import calculate
from .commands import search_commands, command_for_id, url_for

MAX_APPS, MAX_COMMANDS, MAX_FILES = 8, 4, 8
TOP_HIT_SCORE = 700

KIND_LABELS = {
    "app": "Application", "pref": "Settings Panel", "file": "File", "folder": "Folder",
    "command": "Command", "calc": "Calculator", "url": "Link", "web": "Web Search", "shell": "Terminal",
}


class Result:
    def __init__(self, kind, title, id, subtitle="", payload="", path=None, icon=None,
                 score=0.0, needs_confirm=False, section=""):
        self.kind, self.title, self.id, self.subtitle = kind, title, id, subtitle
        self.payload, self.path, self.icon, self.score = payload, path, icon, score
        self.needs_confirm, self.section = needs_confirm, section

    def copy(self, **changes):
        clone = Result(self.kind, self.title, self.id, self.subtitle, self.payload, self.path,
                       self.icon, self.score, self.needs_confirm, self.section)
        for key, value in changes.items():
            setattr(clone, key, value)
        return clone

    @property
    def label(self):
        return KIND_LABELS[self.kind]

    @property
    def primary_action(self):
        return {
            "app": "Open Application", "pref": "Open Settings", "file": "Open File",
            "folder": "Open Folder", "command": self.title if self.needs_confirm else "Run Command",
            "calc": "Copy Answer", "url": "Open Link", "web": "Search", "shell": "Run in Terminal",
        }[self.kind]

    def __repr__(self):
        return "Result(%s, %r, %.0f)" % (self.kind, self.title, self.score)


def file_result(path, score=0.0):
    home = os.path.expanduser("~")
    parent = os.path.dirname(path)
    if parent == home or parent.startswith(home + "/"):
        parent = "~" + parent[len(home):]
    kind = "folder" if os.path.isdir(path) else "file"
    return Result(kind, os.path.basename(path), "file:" + path, parent, path=path,
                  icon=("path", path), score=score)


def build_results(query, prefs, history, apps, file_results):
    """`apps` has search(query, include) and find(id); `file_results` holds
    the latest file hits for this query."""
    query = query.strip()
    results = []
    if not query:
        if prefs["suggestions"]:
            results = suggestions(history, apps)
        return results
    if query.startswith(">"):
        command = query[1:].strip()
        if command:
            results.append(Result("shell", command, "shell", "Run in Terminal", command,
                                  icon=("name", "utilities-terminal"), section="Terminal"))
        return results

    if prefs["calculator"]:
        value = calculate(query)
        if value is not None:
            results.append(Result("calc", "= " + value, "calc", query, value,
                                  icon=("name", "accessories-calculator"), section="Calculator"))
    url = url_for(query)
    if url:
        results.append(Result("url", "Open " + query, "url", url, url,
                              icon=("name", "web-browser"), section="Link"))

    groups = [
        apps.search(query, prefs["search_apps"]),
        # Kigo Settings stays findable with commands off.
        search_commands(query, prefs["search_commands"]),
        [r.copy() for r in file_results] if prefs["search_files"] else [],
    ]
    for group in groups:
        for result in group:
            result.score += history.boost(result.id)

    # Top Hit: the single best match across kinds, Spotlight-style.
    best = None
    for g, group in enumerate(groups):
        for r, result in enumerate(group):
            if result.score >= TOP_HIT_SCORE and (best is None or result.score > groups[best[0]][best[1]].score):
                best = (g, r)
    if best:
        top = groups[best[0]].pop(best[1])
        top.section = "Top Hit"
        results.append(top)

    for group, limit, section in zip(groups, (MAX_APPS, MAX_COMMANDS, MAX_FILES),
                                     ("Applications", "Commands", "Files")):
        for result in sorted(group, key=lambda r: -r.score)[:limit]:
            result.section = section
            results.append(result)

    # Fallbacks, always last: search the web, or run it as a command.
    fallbacks = "Use “%s” with…" % query
    web = prefs.web_search_url(query)
    if web:
        results.append(Result("web", "Search the web for “%s”" % query, "web",
                              ["", "DuckDuckGo", "Google", "Bing"][prefs["web_search"]], web,
                              icon=("name", "web-browser"), section=fallbacks))
    results.append(Result("shell", "Run “%s”" % query, "shell", "in Terminal (or type > first)",
                          query, icon=("name", "utilities-terminal"), section=fallbacks))
    return results


def suggestions(history, apps):
    results = []
    for key in history.top(8):
        result = None
        if key.startswith(("app:", "pref:")):
            result = apps.find(key)
        elif key.startswith("file:"):
            path = key[5:]
            if os.path.exists(path):
                result = file_result(path)
        else:
            result = command_for_id(key)
        if result:
            result.section = "Suggestions"
            results.append(result)
    return results
