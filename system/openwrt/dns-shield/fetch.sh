#!/bin/sh
# fetch.sh <package>: downloads the package and every dependency not installed yet into the current directory.
todo=$1
seen=' '
while [ -n "$todo" ]; do
	set -- $todo
	p=$1
	shift
	todo=$*
	case $seen in *" $p "*) continue ;; esac
	seen="$seen$p "
	opkg status "$p" | grep -q 'install ok installed' && continue
	opkg download "$p" >/dev/null 2>&1 || { echo "dns-shield: cannot download $p"; exit 1; }
	todo="$todo $(opkg info "$p" | sed -n 's/^Depends: //p' | head -n 1 | sed 's/([^)]*)//g' | tr ',' ' ')"
done
