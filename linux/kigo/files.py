"""Files and folders by name: a background index of your home folder (names
only, rebuilt every few minutes), scored with the same fuzzy matcher."""
import os
import threading
import time

from .fuzzy import fuzzy_score

MAX_ENTRIES = 400_000
MAX_SCANNED = 3000
MAX_RESULTS = 24
SKIP = {"node_modules", "__pycache__", "build", "target", "DerivedData", "Pods", "venv", "site-packages",
        "snap", "dist"}


class FileIndex:
    def __init__(self, root=None):
        self.root = root or os.path.expanduser("~")
        self.entries = []    # (lower name, path)
        self.built = 0.0
        self.building = False
        self.lock = threading.Lock()

    def refresh_if_stale(self, age=300):
        if not self.building and time.time() - self.built > age:
            self.building = True
            threading.Thread(target=self._build, daemon=True).start()

    def _build(self):
        entries = []
        try:
            stack = [self.root]
            while stack and len(entries) < MAX_ENTRIES:
                folder = stack.pop()
                try:
                    with os.scandir(folder) as it:
                        for entry in it:
                            name = entry.name
                            if name.startswith(".") or name in SKIP:
                                continue
                            entries.append((name.lower(), entry.path))
                            try:
                                if entry.is_dir(follow_symlinks=False):
                                    stack.append(entry.path)
                            except OSError:
                                pass
                except OSError:
                    continue
        finally:
            with self.lock:
                self.entries = entries
            self.built = time.time()
            self.building = False

    def search(self, query):
        """[(score, path)] best first; runs off the main thread."""
        text = query.strip()
        if len(text) < 2:
            return []
        # Narrow by the longest word, like Spotlight's name index; fuzzy does the rest.
        word = max(text.lower().split(), key=len)
        with self.lock:
            entries = self.entries
        home = os.path.expanduser("~")
        home_depth = home.count("/")
        hits = []
        for lower, path in entries:
            if word in lower:
                name = os.path.basename(path)
                score = fuzzy_score(text, name)
                if score > 0:
                    # Below apps and commands; documents near home beat deep paths.
                    score = score * 0.75 + 15
                    if path.startswith((home + "/Desktop/", home + "/Downloads/")):
                        score += 10
                    score -= max(0, path.count("/") - home_depth) * 2
                    hits.append((score, path))
                if len(hits) >= MAX_SCANNED:
                    break
        hits.sort(key=lambda h: -h[0])
        return hits[:MAX_RESULTS]
