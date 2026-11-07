"""The shortcut as Kigo's own X11 key grab, for sessions where GNOME's
custom shortcut never reaches it: a second GNOME session (Beam's virtual
desktop on :20) runs its own settings daemons, which may not pick up Kigo's
binding. Where GNOME already holds the key the grab fails and GNOME's
shortcut runs Kigo's toggle command as before. Xlib through ctypes, all on
the main thread (events arrive through a GLib watch on the connection)."""
import ctypes
import ctypes.util
import os

from gi.repository import GLib

MODIFIERS = {"<Alt>space": 1 << 3, "<Primary>space": 1 << 2, "<Super>space": 1 << 6}
# The same key with Caps Lock and/or Num Lock on.
LOCKS = (0, 1 << 1, 1 << 4, (1 << 1) | (1 << 4))
KEY_PRESS = 2
SPACE = 0x20

_ErrorHandler = ctypes.CFUNCTYPE(ctypes.c_int, ctypes.c_void_p, ctypes.c_void_p)


def _xlib():
    path = ctypes.util.find_library("X11")
    if not path:
        return None
    x = ctypes.CDLL(path)
    x.XOpenDisplay.restype = ctypes.c_void_p
    x.XOpenDisplay.argtypes = [ctypes.c_char_p]
    x.XDefaultRootWindow.restype = ctypes.c_ulong
    x.XDefaultRootWindow.argtypes = [ctypes.c_void_p]
    x.XKeysymToKeycode.restype = ctypes.c_ubyte
    x.XKeysymToKeycode.argtypes = [ctypes.c_void_p, ctypes.c_ulong]
    x.XGrabKey.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_uint, ctypes.c_ulong,
                           ctypes.c_int, ctypes.c_int, ctypes.c_int]
    x.XSync.argtypes = [ctypes.c_void_p, ctypes.c_int]
    x.XConnectionNumber.argtypes = [ctypes.c_void_p]
    x.XPending.argtypes = [ctypes.c_void_p]
    x.XNextEvent.argtypes = [ctypes.c_void_p, ctypes.c_void_p]
    x.XCloseDisplay.argtypes = [ctypes.c_void_p]
    x.XSetErrorHandler.restype = ctypes.c_void_p
    x.XSetErrorHandler.argtypes = [ctypes.c_void_p]
    return x


class X11Hotkey:
    def __init__(self, callback):
        self.callback = callback
        self.x = None
        self.display = None
        self.watch = None

    def grab(self, accel):
        """True when Kigo now owns the key itself."""
        self.release()
        if not os.environ.get("DISPLAY") or os.environ.get("WAYLAND_DISPLAY") or accel not in MODIFIERS:
            return False
        x = _xlib()
        display = x.XOpenDisplay(None) if x else None
        if not display:
            return False
        failed = []
        # A grab someone else holds comes back as BadAccess; catch it here
        # instead of letting the process-wide handler (GDK's) see it.
        handler = _ErrorHandler(lambda _d, _e: failed.append(1) or 0)
        previous = x.XSetErrorHandler(ctypes.cast(handler, ctypes.c_void_p))
        code = x.XKeysymToKeycode(display, SPACE)
        root = x.XDefaultRootWindow(display)
        for lock in LOCKS:
            x.XGrabKey(display, code, MODIFIERS[accel] | lock, root, 1, 1, 1)
        x.XSync(display, 0)
        x.XSetErrorHandler(previous)
        if failed:
            x.XCloseDisplay(display)   # drops any half-made grabs
            return False
        self.x, self.display = x, display
        self.watch = GLib.io_add_watch(x.XConnectionNumber(display), GLib.PRIORITY_DEFAULT,
                                       GLib.IO_IN, self._events)
        return True

    def _events(self, *_):
        event = ctypes.create_string_buffer(192)   # sizeof(XEvent)
        while self.x.XPending(self.display):
            self.x.XNextEvent(self.display, event)
            if int.from_bytes(event.raw[:4], "little") == KEY_PRESS:
                self.callback()
        return True

    def release(self):
        if self.watch:
            GLib.source_remove(self.watch)
            self.watch = None
        if self.display:
            self.x.XCloseDisplay(self.display)
            self.display = None
