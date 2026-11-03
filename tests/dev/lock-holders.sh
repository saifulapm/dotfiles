#!/usr/bin/env bash
# lock-holders.sh <file>: prints "pid: command line" for each process with an fd open on <file>, so a check stuck on the lock names who holds it.
{
target=$(realpath -- "$1") || exit 1
for fd in /proc/[0-9]*/fd/*; do
  [ "$(readlink -- "$fd" 2>/dev/null)" = "$target" ] || continue
  pid=${fd#/proc/}
  pid=${pid%%/*}
  printf '%s: %s\n' "$pid" "$(tr '\0' ' ' <"/proc/$pid/cmdline" 2>/dev/null)"
done | sort -u
exit 0
}
