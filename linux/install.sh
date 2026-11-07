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
cp -R "$here/kigo" "$here/kigo.svg" "$here/VERSION" "$app.new/"
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

mkdir -p "$share/icons/hicolor/scalable/apps" "$share/applications"
cp "$here/kigo.svg" "$share/icons/hicolor/scalable/apps/kigo.svg"
cat > "$share/applications/com.bluevisor.kigo.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=Kigo
Comment=Launcher: Alt+Space, type, Enter
Exec=$HOME/.local/bin/kigo
Icon=kigo
Categories=Utility;
Keywords=launcher;search;spotlight;raycast;
StartupNotify=false
DESKTOP
gtk-update-icon-cache -q "$share/icons/hicolor" 2>/dev/null || true

[ "$1" = "--update" ] && exit 0
# Restart a running copy on the new files, then show it.
"$HOME/.local/bin/kigo" --quit >/dev/null 2>&1 || true
sleep 1
nohup "$HOME/.local/bin/kigo" --background >/dev/null 2>&1 &
sleep 2
"$HOME/.local/bin/kigo" --show >/dev/null 2>&1 &
echo "Kigo $(cat "$here/VERSION") installed. Press Alt+Space."
