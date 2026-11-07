"""Kigo for Linux: a Spotlight and Raycast style launcher. Alt+Space, type, Enter."""
import os

_here = os.path.dirname(os.path.abspath(__file__))
# Installed: app/VERSION next to the package; in the source tree: the repo's.
for _candidate in (os.path.join(_here, "..", "VERSION"), os.path.join(_here, "..", "..", "VERSION")):
    if os.path.exists(_candidate):
        with open(_candidate) as _f:
            VERSION = _f.read().strip()
        break
else:
    VERSION = "0"

# kigo.svg, for the window and menu icon: installed next to the package, or haiku/ in the tree.
ICON_DIRS = [os.path.join(_here, ".."), os.path.join(_here, "..", "..", "haiku")]
