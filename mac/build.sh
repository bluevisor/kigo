#!/bin/sh
# Builds Kigo.app for macOS into mac/dist, signed with the Developer ID.
#   mac/build.sh             build mac/dist/Kigo.app
#   mac/build.sh --install   and replace /Applications/Kigo.app, then start it
#   mac/build.sh --release   and notarize it into mac/dist/kigo-<version>-macos.zip,
#                            the asset Kigo's updater downloads (KIGO_NOTARY_PROFILE
#                            names the notarytool keychain profile)
set -e
cd "$(dirname "$0")"
VERSION=$(tr -d ' \n' < ../VERSION)
APP=dist/Kigo.app

swift build -c release --arch arm64 --arch x86_64
BIN=$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/Kigo

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Kigo"

# The icon: the ginkgo leaf from the Haiku package, on a macOS tile.
ICONSET=.build/Kigo.iconset
if [ ! -f .build/Kigo.icns ] || [ ../haiku/kigo.svg -nt .build/Kigo.icns ]; then
	rm -rf "$ICONSET" && mkdir -p "$ICONSET"
	swift scripts/mkicon.swift ../haiku/kigo.svg .build/icon-1024.png
	for s in 16 32 128 256 512; do
		sips -z $s $s .build/icon-1024.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
		d=$((s * 2))
		sips -z $d $d .build/icon-1024.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
	done
	iconutil -c icns "$ICONSET" -o .build/Kigo.icns
fi
cp .build/Kigo.icns "$APP/Contents/Resources/Kigo.icns"
cp ../haiku/kigo.svg "$APP/Contents/Resources/kigo-leaf.svg"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key><string>Kigo</string>
	<key>CFBundleIdentifier</key><string>com.bluevisor.kigo</string>
	<key>CFBundleName</key><string>Kigo</string>
	<key>CFBundleDisplayName</key><string>Kigo</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleShortVersionString</key><string>$VERSION</string>
	<key>CFBundleVersion</key><string>$VERSION</string>
	<key>CFBundleIconFile</key><string>Kigo</string>
	<key>LSMinimumSystemVersion</key><string>14.0</string>
	<key>LSUIElement</key><true/>
	<key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
	<key>NSAppleEventsUsageDescription</key><string>Kigo runs shell commands in Terminal and asks Finder and System Events to empty the Trash, restart, shut down, log out or switch dark mode when you pick those commands.</string>
	<key>NSHumanReadableCopyright</key><string>© 2026 John Zheng</string>
</dict>
</plist>
PLIST

IDENTITY=${KIGO_SIGN_IDENTITY:-$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application[^"]*\)".*/\1/p' | head -1)}
# Notarization needs a secure timestamp; local builds skip the round trip.
TIMESTAMP=--timestamp=none
[ "$1" = "--release" ] && TIMESTAMP=--timestamp
if [ -n "$IDENTITY" ]; then
	codesign --force --options runtime $TIMESTAMP --sign "$IDENTITY" "$APP"
else
	codesign --force --sign - "$APP"
fi
echo "built $APP ($VERSION, signed by ${IDENTITY:-ad hoc})"

if [ "$1" = "--install" ]; then
	pkill -x Kigo 2>/dev/null && sleep 0.5 || true
	rm -rf /Applications/Kigo.app
	cp -R "$APP" /Applications/Kigo.app
	open /Applications/Kigo.app
	echo "installed /Applications/Kigo.app"
fi

if [ "$1" = "--release" ]; then
	ZIP=dist/kigo-$VERSION-macos.zip
	rm -f "$ZIP"
	ditto -c -k --keepParent "$APP" "$ZIP"
	xcrun notarytool submit "$ZIP" --keychain-profile "${KIGO_NOTARY_PROFILE:-terminal-cam-notary}" --wait
	xcrun stapler staple "$APP"
	# Zip again so the download carries the stapled ticket.
	rm -f "$ZIP"
	ditto -c -k --keepParent "$APP" "$ZIP"
	echo "released $ZIP"
fi
