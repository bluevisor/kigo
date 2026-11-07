#!/bin/sh
# Installs Kigo for the current user, no root needed:
#   ~/.local/share/kigo/app   the program (Python 3 + GTK 3)
#   ~/.local/bin/kigo         the command
#   a menu entry and icon; Kigo itself adds the Alt+Space shortcut and the
#   login item from its settings when it starts.
#   sh install.sh             install and start Kigo
#   sh install.sh --update    replace the program only (the updater uses this)
set -e
here=$(cd "$(dirname "$0")" && pwd)
share=${XDG_DATA_HOME:-$HOME/.local/share}
app=$share/kigo/app

if ! python3 -c 'import gi; gi.require_version("Gtk", "3.0"); from gi.repository import Gtk' 2>/dev/null; then
	echo "Kigo needs Python 3 with GTK 3 (Debian/Ubuntu: sudo apt install python3-gi gir1.2-gtk-3.0)" >&2
	exit 1
fi

mkdir -p "$share/kigo"
rm -rf "$app.new"
mkdir -p "$app.new"
cp -R "$here/kigo" "$here/kigo.svg" "$here/com.bluevisor.kigo.png" "$here/VERSION" "$app.new/"
rm -rf "$app.old"
[ -d "$app" ] && mv "$app" "$app.old"
mv "$app.new" "$app"
rm -rf "$app.old"

mkdir -p "$HOME/.local/bin"
cat > "$HOME/.local/bin/kigo" <<WRAPPER
#!/bin/sh
PYTHONPATH="$app\${PYTHONPATH:+:\$PYTHONPATH}" exec python3 -m kigo "\$@"
WRAPPER
chmod +x "$HOME/.local/bin/kigo"

# The app icon is Kigo's tile (the same as on the Mac); the bare leaf
# (kigo.svg) stays inside the app for its own logo.
icons=$share/icons/hicolor
mkdir -p "$icons/512x512/apps" "$share/applications"
cp "$here/com.bluevisor.kigo.png" "$icons/512x512/apps/com.bluevisor.kigo.png"
rm -f "$icons/scalable/apps/kigo.svg"    # the bare leaf, from 0.1.14
cat > "$share/applications/com.bluevisor.kigo.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=Kigo
Comment=Launcher: Alt+Space, type, Enter
Exec=$HOME/.local/bin/kigo
Icon=com.bluevisor.kigo
Categories=Utility;
Keywords=launcher;search;spotlight;raycast;
StartupNotify=false
DESKTOP
# A stale icon-theme.cache (another app's) hides new icons; this folder has
# no index.theme, so rebuild it with -t, or GTK never finds Kigo's icon.
[ -f "$icons/icon-theme.cache" ] && { gtk-update-icon-cache -q -f -t "$icons" 2>/dev/null || rm -f "$icons/icon-theme.cache"; }

[ "$1" = "--update" ] && exit 0
# Restart a running copy on the new files, then show it.
"$HOME/.local/bin/kigo" --quit >/dev/null 2>&1 || true
sleep 1
nohup "$HOME/.local/bin/kigo" --background >/dev/null 2>&1 &
sleep 2
"$HOME/.local/bin/kigo" --show >/dev/null 2>&1 &
echo "Kigo $(cat "$here/VERSION") installed. Press Alt+Space."
