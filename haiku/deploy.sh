#!/bin/sh
# Copies the tree to the Haiku VM, builds it there and (re)starts Kigo.
#   haiku/deploy.sh             build + restart the built copy
#   haiku/deploy.sh --install   build the package and install it (Kigo sets up
#                               its hotkey filter and login item on launch)
#   haiku/deploy.sh --no-run    build only
# HOST defaults to the UTM debug VM's ssh alias.
set -e
HOST=${HOST:-haiku-dbg}
cd "$(dirname "$0")/.."

# The VM clock resets to 1970 on boot; make minds.
ssh "$HOST" "date -u -s '$(date -u '+%Y-%m-%d %H:%M:%S')'" >/dev/null

COPYFILE_DISABLE=1 tar --no-xattrs --exclude ./build --exclude ./dist --exclude ./.git \
	--exclude ./.haiku-sdk -czf - . \
	| ssh "$HOST" 'rm -rf ~/src/kigo/src ~/src/kigo/hotkey && mkdir -p ~/src/kigo && tar xzf - -C ~/src/kigo 2>/dev/null'
ssh "$HOST" 'cd ~/src/kigo && make -j8 2>&1 | grep -Ev "^(g\+\+|rc|xres|mimeset) " | tail -40; test -x build/Kigo'

case "$1" in
	--no-run) ;;
	--install)
		ssh "$HOST" 'cd ~/src/kigo && make install 2>&1 | grep -E "hpkg|rror" | tail -5'
		echo "Kigo installed and started on $HOST"
		;;
	*)
		ssh "$HOST" 'cd ~/src/kigo && haiku/stop.sh; sleep 0.5; (build/Kigo > ~/config/settings/Kigo-stdout.log 2>&1 &)'
		echo "Kigo started on $HOST (log: ~/config/settings/Kigo-stdout.log)"
		;;
esac
