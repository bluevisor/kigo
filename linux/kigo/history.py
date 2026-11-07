"""What you opened and when, for frecency ranking and suggestions. Same file
format as the Haiku and Mac apps: count<TAB>last-used<TAB>id<TAB>title."""
import math
import os
import time

MAX_ITEMS = 300


def data_dir():
    base = os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share")
    path = os.path.join(base, "kigo")
    os.makedirs(path, exist_ok=True)
    return path


class History:
    def __init__(self, path=None):
        self.path = path or os.path.join(data_dir(), "history")
        self.items = {}

    def load(self):
        self.items = {}
        try:
            with open(self.path, encoding="utf-8") as f:
                for line in f:
                    parts = line.rstrip("\n").split("\t", 3)
                    if len(parts) == 4:
                        try:
                            self.items[parts[2]] = [int(parts[0]), float(parts[1]), parts[3]]
                        except ValueError:
                            pass
        except OSError:
            pass

    def save(self):
        temp = self.path + ".new"
        with open(temp, "w", encoding="utf-8") as f:
            for key, (count, used, title) in self.items.items():
                f.write("%d\t%d\t%s\t%s\n" % (count, used, key, title))
        os.replace(temp, self.path)

    def clear(self):
        self.items = {}
        self.save()

    @staticmethod
    def _frecency(item, now):
        days = max(0.0, (now - item[1]) / 86400)
        # Recent use counts for more; a week-old launch is worth about half.
        return math.log2(1 + item[0]) / (1 + days / 7)

    def record(self, key, title):
        item = self.items.setdefault(key, [0, 0.0, title])
        item[0] += 1
        item[1] = time.time()
        item[2] = title
        if len(self.items) > MAX_ITEMS:
            now = time.time()
            worst = min(self.items, key=lambda k: self._frecency(self.items[k], now))
            del self.items[worst]
        self.save()

    def boost(self, key):
        item = self.items.get(key)
        return self._frecency(item, time.time()) * 60 if item else 0.0

    def top(self, count):
        now = time.time()
        return sorted(self.items, key=lambda k: -self._frecency(self.items[k], now))[:count]
