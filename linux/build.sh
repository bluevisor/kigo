#!/bin/sh
# Packs Kigo for Linux: linux/dist/kigo-<version>-linux.tar.gz, the release
# asset the updater downloads. Pure Python, so one archive fits every arch.
#   linux/build.sh            the archive
#   linux/build.sh --test     run the core tests first
set -e
cd "$(dirname "$0")"
VERSION=$(tr -d ' \n' < ../VERSION)
[ "$1" = "--test" ] && python3 -m unittest discover -s tests
stage=dist/kigo-$VERSION
rm -rf dist && mkdir -p "$stage"
cp -R kigo install.sh "$stage/"
cp ../haiku/kigo.svg ../LICENSE icons/com.bluevisor.kigo.png "$stage/"
echo "$VERSION" > "$stage/VERSION"
find "$stage" -name __pycache__ -prune -exec rm -rf {} +
COPYFILE_DISABLE=1 tar --no-xattrs -czf "dist/kigo-$VERSION-linux.tar.gz" -C dist "kigo-$VERSION"
echo "built linux/dist/kigo-$VERSION-linux.tar.gz"
