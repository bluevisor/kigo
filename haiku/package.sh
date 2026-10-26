#!/bin/bash
# Builds Kigo and wraps it in an .hpkg. Run ON Haiku:
#   haiku/package.sh                 -> dist/kigo-<version>-<rev>-<arch>.hpkg
#   KIGO_PKG_REV=2 haiku/package.sh   bump the package revision
#   KIGO_BUILD=build/x86_64 KIGO_ARCH=x86_64 haiku/package.sh
#                                    package cross-built binaries (haiku/cross.sh)
# Install by copying the .hpkg into ~/config/packages; on first launch Kigo
# installs its hotkey filter and starts itself at login.
set -eo pipefail
cd "$(dirname "$0")/.."

version=$(cat VERSION)
rev=${KIGO_PKG_REV:-1}
arch=${KIGO_ARCH:-$(getarch)}
out="dist/kigo-$version-$rev-$arch.hpkg"

build=${KIGO_BUILD:-build}
if [ -z "$KIGO_BUILD" ]; then
	make -j8 >/dev/null
else
	# A cross-built binary: add the resources here, where rc and xres run.
	rc -o "$build/Kigo.rsrc" haiku/Kigo.rdef
	xres -o "$build/Kigo" "$build/Kigo.rsrc"
	rm "$build/Kigo.rsrc"
	mimeset -f "$build/Kigo"
fi

stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
mkdir -p "$stage/apps" "$stage/bin" "$stage/data/deskbar/menu/Applications" \
	"$stage/data/kigo" "$stage/documentation/packages/kigo"

copyattr -d "$build/Kigo" "$stage/apps/Kigo"
ln -s ../apps/Kigo "$stage/bin/kigo"
ln -s ../../../../apps/Kigo "$stage/data/deskbar/menu/Applications/Kigo"
# Data, not an add-on: Kigo copies it into the non-packaged filters folder
# itself, so swapping this package never unloads a filter in use.
install -m 755 "$build/KigoHotkey" "$stage/data/kigo/KigoHotkey"
cp README.md LICENSE "$stage/documentation/packages/kigo/"

# 32-bit Haiku (x86_gcc2h) runs a modern-gcc binary against its secondary
# x86 libraries, so require those (haiku_x86, lib:..._x86) as HaikuPorts does.
secondary=()
[ "$arch" = x86_gcc2 ] && secondary=(-e 's/^\thaiku$/\thaiku\n\thaiku_x86/' -e 's/^\t\(lib:[a-z_+]*\)$/\t\1_x86/')
sed -e "s/@VERSION@/$version/g" -e "s/@REVISION@/$rev/g" -e "s/@ARCH@/$arch/g" "${secondary[@]}" \
	haiku/PackageInfo.in > "$stage/.PackageInfo"

mkdir -p dist
rm -f "$out"
package create -C "$stage" "$out"
echo "$out"
