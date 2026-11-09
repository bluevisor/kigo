"""The ported matcher, calculator, links and ranking behave like the Haiku and Mac apps."""
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from kigo.calculator import calculate  # noqa: E402
from kigo.commands import search_commands, url_for  # noqa: E402
from kigo.fuzzy import fuzzy_score  # noqa: E402
from kigo.history import History  # noqa: E402
from kigo.model import Result, build_results, section_order  # noqa: E402
from kigo.files import FileIndex  # noqa: E402
from kigo.prefs import Prefs  # noqa: E402


class Apps:
    def __init__(self, names):
        self.names = names

    def search(self, query, include=True):
        out = []
        for name in self.names if include else []:
            score = fuzzy_score(query, name)
            if score > 0:
                out.append(Result("app", name, "app:" + name, score=score + 40))
        return out

    def find(self, key):
        return None


class CoreTests(unittest.TestCase):
    def test_fuzzy_order(self):
        self.assertEqual(fuzzy_score("firefox", "Firefox"), 1000)
        prefix = fuzzy_score("fir", "Firefox")
        word = fuzzy_score("studio", "Visual Studio Code")
        acronym = fuzzy_score("vsc", "Visual Studio Code")
        substring = fuzzy_score("ref", "Firefox")
        subsequence = fuzzy_score("ffx", "Firefox")
        self.assertGreater(prefix, word)
        self.assertGreater(word, acronym)
        self.assertGreater(acronym, substring)
        self.assertGreater(substring, subsequence)
        self.assertGreater(subsequence, 0)
        self.assertEqual(fuzzy_score("xyz", "Firefox"), 0)
        self.assertGreater(fuzzy_score("sys mon", "System Monitor"), 0)
        self.assertEqual(fuzzy_score("sys xyz", "System Monitor"), 0)

    def test_matches_swift_and_cpp(self):
        # The same numbers the C++ and Swift matchers give.
        self.assertEqual(fuzzy_score("saf", "Safari"), 898.5)
        self.assertEqual(fuzzy_score("pos", "WebPositive"), 797)

    def test_calculator(self):
        self.assertEqual(calculate("2+2"), "4")
        self.assertEqual(calculate("sqrt(2)*10^3"), "1414.213562")
        self.assertEqual(calculate("= 10/4"), "2.5")
        self.assertIsNone(calculate("2pi"))
        self.assertEqual(calculate("2*pi"), "6.283185307")
        self.assertEqual(calculate("5!"), "120")
        self.assertEqual(calculate("3(4+5)"), "27")
        self.assertIsNone(calculate("1/0"))
        self.assertIsNone(calculate("-5"))
        self.assertIsNone(calculate("firefox"))
        self.assertEqual(calculate("2e3+1"), "2001")

    def test_urls(self):
        self.assertEqual(url_for("haiku-os.org"), "https://haiku-os.org")
        self.assertEqual(url_for("github.com/bluevisor/kigo"), "https://github.com/bluevisor/kigo")
        self.assertIsNone(url_for("hello world.com"))
        self.assertIsNone(url_for("v1.2"))

    def test_commands(self):
        self.assertEqual(search_commands("lock")[0].id, "cmd:lock")
        self.assertEqual(search_commands("reboot")[0].id, "cmd:restart")
        self.assertEqual(search_commands("sleep", False), [])

    def test_ranking(self):
        with tempfile.TemporaryDirectory() as tmp:
            prefs = Prefs(os.path.join(tmp, "settings.json"))
            history = History(os.path.join(tmp, "history"))
            apps = Apps(["Firefox", "Files", "Terminal"])
            results = build_results("fire", prefs, history, apps, [])
            self.assertEqual(results[0].title, "Firefox")
            self.assertEqual(results[0].section, "Top Hit")
            self.assertEqual(results[-1].kind, "shell")
            self.assertEqual(results[-2].kind, "web")
            self.assertEqual([r.kind for r in build_results("2+3", prefs, history, apps, [])][0], "calc")
            history.record("app:Files", "Files")
            self.assertEqual(build_results("fi", prefs, history, apps, [])[0].title, "Files")

    def test_settings_opens_kigo_settings(self):
        with tempfile.TemporaryDirectory() as tmp:
            prefs = Prefs(os.path.join(tmp, "settings.json"))
            history = History(os.path.join(tmp, "history"))
            apps = Apps(["Settings", "Files"])
            for _ in range(50):
                history.record("app:Settings", "Settings")
            for query in ("settings", "Sett", "kigo set"):
                top = build_results(query, prefs, history, apps, [])[0]
                self.assertEqual((top.id, top.section), ("cmd:settings", "Top Hit"), query)
            self.assertEqual(build_results("set", prefs, history, apps, [])[0].title, "Settings")

    def test_section_order(self):
        self.assertEqual(section_order([[428], [380], [1000, 900]]), [2, 0, 1])
        self.assertEqual(section_order([[900], [900], [900]]), [0, 1, 2])
        self.assertEqual(section_order([[], [650], []]), [1, 0, 2])

    def test_index_reaches_shallow_folders_first(self):
        import kigo.files as files
        with tempfile.TemporaryDirectory() as tmp:
            deep = os.path.join(tmp, "Developer")
            for i in range(30):
                os.makedirs(os.path.join(deep, "p%d" % i, "a", "b"))
            os.makedirs(os.path.join(tmp, "src", "temino"))
            cap, files.MAX_ENTRIES = files.MAX_ENTRIES, 40
            try:
                index = FileIndex(tmp)
                index._build()
            finally:
                files.MAX_ENTRIES = cap
            self.assertTrue(any(p.endswith("/src/temino") for _, p in index.entries))


if __name__ == "__main__":
    unittest.main()
