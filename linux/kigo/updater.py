"""Over-the-air updates from GitHub releases, like the Haiku and Mac apps:
once a day (and from Check for Updates) it reads the latest release,
downloads kigo-<version>-linux.tar.gz, checks it against the SHA-256 GitHub
publishes for it, installs it over this copy and restarts."""
import fcntl
import hashlib
import json
import os
import shutil
import subprocess
import tarfile
import tempfile
import threading
import time
import urllib.request

from gi.repository import GLib

from . import VERSION
from .prefs import config_dir
from .history import data_dir
from .setup import WRAPPER, installed

LATEST = "https://api.github.com/repos/bluevisor/kigo/releases/latest"
RELEASES = "https://github.com/bluevisor/kigo/releases"
SUFFIX = "-linux.tar.gz"
DAY = 86400
# The installed copy's version, which another session's Kigo may have updated.
DISK_VERSION = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "VERSION")


def disk_version():
    try:
        with open(DISK_VERSION) as f:
            return f.read().strip()
    except OSError:
        return VERSION


def is_newer(a, b):
    def parts(v):
        return [int(p) if p.isdigit() else 0 for p in v.split(".")]
    x, y = parts(a), parts(b)
    n = max(len(x), len(y))
    return x + [0] * (n - len(x)) > y + [0] * (n - len(y))


class Updater:
    def __init__(self, app):
        self.app = app
        self.checking = False
        self.stamp = os.path.join(config_dir(), "update-checked")

    def start(self):
        self._check_if_due()
        GLib.timeout_add_seconds(4 * 3600, lambda: self._check_if_due() or True)

    def _check_if_due(self):
        # Kigo in another session (Beam's virtual desktop, say) installed a
        # newer copy: start on it too.
        if installed() and is_newer(disk_version(), VERSION):
            return self._restart()
        if not self.app.prefs["updates"]:
            return
        try:
            last = float(open(self.stamp).read())
        except (OSError, ValueError):
            last = 0
        if time.time() - last >= DAY:
            self.check(manual=False)

    def check(self, manual):
        if self.checking:
            return
        self.checking = True
        with open(self.stamp, "w") as f:
            f.write(str(time.time()))
        threading.Thread(target=self._run, args=(manual,), daemon=True).start()

    def _report(self, manual, title, text):
        self.checking = False
        if manual:
            GLib.idle_add(self.app.message, title, text)

    def _run(self, manual):
        try:
            request = urllib.request.Request(LATEST, headers={"Accept": "application/vnd.github+json",
                                                              "User-Agent": "Kigo/" + VERSION})
            release = json.load(urllib.request.urlopen(request, timeout=30))
        except (OSError, ValueError):
            return self._report(manual, "Can't check for updates", "Couldn't reach GitHub.")
        version = release.get("tag_name", "").lstrip("v")
        if not version or not is_newer(version, VERSION):
            return self._report(manual, "Kigo is up to date", "Kigo %s is the latest version." % VERSION)
        asset = next((a for a in release.get("assets", []) if a.get("name", "").endswith(SUFFIX)), None)
        if asset is None or not installed():
            # No Linux build, or a source checkout: point at the release instead.
            if manual:
                GLib.idle_add(lambda: subprocess.Popen(["xdg-open", RELEASES]) and False)
            return self._report(False, "", "")
        # One install at a time across sessions; the one that waited finds
        # the files already new and just restarts.
        lock = open(os.path.join(data_dir(), "update.lock"), "w")
        fcntl.flock(lock, fcntl.LOCK_EX)
        if not is_newer(version, disk_version()):
            lock.close()
            self.checking = False
            return GLib.idle_add(self._restart)
        staging = tempfile.mkdtemp(prefix="kigo-update-")
        try:
            archive = os.path.join(staging, asset["name"])
            urllib.request.urlretrieve(asset["browser_download_url"], archive)
            digest = (asset.get("digest") or "").removeprefix("sha256:")
            with open(archive, "rb") as f:
                actual = hashlib.sha256(f.read()).hexdigest()
            if not digest or digest != actual:
                return self._report(True, "Can't update Kigo", "The download didn't match its checksum.")
            with tarfile.open(archive) as tar:
                for member in tar.getmembers():
                    if member.name.startswith("/") or ".." in member.name.split("/"):
                        return self._report(True, "Can't update Kigo", "The download looks wrong.")
                tar.extractall(staging)
            folder = next(os.path.join(staging, d) for d in os.listdir(staging)
                          if os.path.isfile(os.path.join(staging, d, "install.sh")))
            if subprocess.run(["sh", os.path.join(folder, "install.sh"), "--update"]).returncode != 0:
                return self._report(True, "Can't update Kigo", "The installer failed.")
        except (OSError, StopIteration, tarfile.TarError):
            return self._report(manual, "Can't update Kigo", "The download failed.")
        finally:
            shutil.rmtree(staging, ignore_errors=True)
            lock.close()
        GLib.idle_add(self._restart)

    def _restart(self):
        # The new copy starts once this one has gone (one Kigo per session).
        subprocess.Popen(["sh", "-c", "sleep 1; exec '%s' --background --updated" % WRAPPER],
                         start_new_session=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        self.app.quit()
        return False
