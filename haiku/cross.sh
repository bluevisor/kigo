#!/usr/bin/env bash
# Cross-builds Kigo for Intel Haiku from the Mac and packages it:
#   haiku/cross.sh x86_64      -> dist/kigo-<v>-<rev>-x86_64.hpkg
#   haiku/cross.sh x86         -> dist/kigo-<v>-<rev>-x86_gcc2.hpkg (32-bit,
#                                 built for the gcc 13 secondary arch)
# Compiles in Haiku's cross-compiler image (gcc 13 + an R1/beta5 sysroot),
# then adds resources and packages on a Haiku box (HAIKU_HOST, default
# haiku-dbg): rc, xres, mimeset and package are Haiku's own tools, and they
# handle any architecture's binary. DOCKER_CONTEXT picks the Docker engine
# (amd64 images; Rosetta on Apple silicon). KIGO_PKG_REV sets the revision.
set -euo pipefail
cd "$(dirname "$0")/.."

case "${1:-}" in
	x86_64) base=x86_64-r1beta5; cxx=x86_64-unknown-haiku-g++; pkgarch=x86_64 ;;
	# Plain i586-pc-haiku-g++ is gcc2; the -x86 tools are the gcc 13 ones.
	x86) base=x86_gcc2h-r1beta5; cxx=i586-pc-haiku-g++-x86; pkgarch=x86_gcc2 ;;
	*) echo "usage: haiku/cross.sh x86_64|x86" >&2; exit 2 ;;
esac
host=${HAIKU_HOST:-haiku-dbg}
version=$(cat VERSION)
out=build/$pkgarch

echo ">> $cxx (ghcr.io/haiku/cross-compiler:$base)"
mkdir -p "$out"
docker run --rm --platform linux/amd64 -v "$PWD":/src -w /src \
	"ghcr.io/haiku/cross-compiler:$base" sh -ec "
		flags='-O2 -std=c++17 -Wall -Wno-multichar -DKIGO_VERSION=\"$version\"'
		for f in src/*.cpp; do
			$cxx \$flags -c \$f -o $out/\$(basename \$f .cpp).o &
		done
		wait
		$cxx -o $out/Kigo $out/*.o -lbe
		# BInputServerFilter resolves against the input_server at load time.
		$cxx \$flags -shared -fPIC -o $out/KigoHotkey hotkey/HotkeyFilter.cpp -lbe
		rm -f $out/*.o"

echo ">> packaging for $pkgarch on $host"
src='~/src/kigo-cross'
COPYFILE_DISABLE=1 tar czf - --no-xattrs haiku README.md LICENSE VERSION "$out/Kigo" "$out/KigoHotkey" \
	| ssh "$host" "rm -rf $src && mkdir -p $src && cd $src && tar xzf -"
pkg=$(ssh "$host" "cd $src && KIGO_BUILD=$out KIGO_ARCH=$pkgarch KIGO_PKG_REV=${KIGO_PKG_REV:-1} haiku/package.sh" | tail -1)
mkdir -p dist
scp -q "$host:$src/$pkg" dist/
echo ">> dist/$(basename "$pkg")"
