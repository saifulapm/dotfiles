#!/usr/bin/env bash
# scratch.sh <command...>: runs the command with a TMPDIR of its own under the cache and removes it after, keeping the command's exit code; /tmp is a tmpfs whose per-user quota other sessions' scratch fills.
{
cache=${XDG_CACHE_HOME:-$HOME/.cache}
mkdir -p "$cache" && dir=$(mktemp -d "$cache/dots-test.XXXXXX") || exit 1
TMPDIR=$dir "$@"
rc=$?
rm -rf "$dir"
exit $rc
}
