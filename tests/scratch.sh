#!/usr/bin/env bash
# scratch.sh <command...>: runs the command with a TMPDIR of its own and removes it after, keeping the command's exit code.
{
dir=$(mktemp -d) || exit 1
TMPDIR=$dir "$@"
rc=$?
rm -rf "$dir"
exit $rc
}
