#!/usr/bin/env bash
# lib-lock-holders.sh <file>: prints "pid: command line" for each process with an fd open on <file>, so a check stuck on the lock names who holds it.
{
target=$(realpath -- "$1") || exit 1
find /proc/[0-9]*/fd -maxdepth 1 -lname "$target" 2>/dev/null | cut -d/ -f3 | sort -un | while read -r pid; do
  printf '%s: %s\n' "$pid" "$(tr '\0' ' ' <"/proc/$pid/cmdline" 2>/dev/null)"
done
exit 0
}
