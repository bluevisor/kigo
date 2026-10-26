#!/bin/bash
# Builds Kigo and wraps it in an .hpkg. Run ON Haiku:
#   haiku/package.sh                 -> dist/kigo-<version>-<rev>-<arch>.hpkg
#   KIGO_PKG_REV=2 haiku/package.sh   bump the package revision
# Install by copying the .hpkg into ~/config/packages; on first launch Kigo
# installs its hotkey filter and starts itself at login.
set -eo pipefail
cd "$(dirname "$0")/.."

version=$(cat VERSION)
rev=${KIGO_PKG_REV:-1}
arch=${KIGO_ARCH:-$(getarch)}
out="dist/kigo-$version-$rev-$arch.hpkg"

make -j8 >/dev/null

stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
mkdir -p "$stage/apps" "$stage/bin" "$stage/data/deskbar/menu/Applications" \
	"$stage/data/kigo" "$stage/documentation/packages/kigo"

copyattr -d build/Kigo "$stage/apps/Kigo"
ln -s ../apps/Kigo "$stage/bin/kigo"
ln -s ../../../../apps/Kigo "$stage/data/deskbar/menu/Applications/Kigo"
# Data, not an add-on: Kigo copies it into the non-packaged filters folder
# itself, so swapping this package never unloads a filter in use.
install -m 755 build/KigoHotkey "$stage/data/kigo/KigoHotkey"
cp README.md LICENSE "$stage/documentation/packages/kigo/"

sed -e "s/@VERSION@/$version/g" -e "s/@REVISION@/$rev/g" -e "s/@ARCH@/$arch/g" \
	haiku/PackageInfo.in > "$stage/.PackageInfo"

mkdir -p dist
rm -f "$out"
package create -C "$stage" "$out"
echo "$out"
