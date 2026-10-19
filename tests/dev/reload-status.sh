#!/usr/bin/env bash
# After qs hot-reloads the shell, status times the reload's first frame, not the process's age.
{
repo=$(cd "$(dirname "$0")/../.." && pwd)
# The nested shell runs a copy, so this check's edit never reaches the shell/ the live shell watches.
copy=$(mktemp -d)
cp -a "$repo/shell" "$copy/shell"
# The shell runs ../bin helpers from its own dir.
ln -s "$repo/bin" "$copy/bin"
export DOTS_DEV_SHELL=$copy/shell
source "$(dirname "$0")/lib.sh"
cleanup() { rm -rf "$copy"; }

paper_up() { niri msg -j layers | jq -e 'any(.[]; .namespace == "dots-paper")' >/dev/null; }
until_ok 5000 paper_up
pid=$(systemctl --user show -p MainPID --value "$DOTS_DEV_UNIT")
config=$(tr '\0' '\n' <"/proc/$pid/environ" | sed -n 's/^QS_CONFIG_PATH=//p')
check "the nested shell runs a copy, not $repo/shell" test -n "$config" -a "$config" != "$repo/shell"

first_frame() { shell_status | jq -e '.firstFrameMs | numbers' 2>/dev/null; }
until_ok 5000 first_frame >/dev/null
old=$(first_frame)
# 3 s on, the process's age is well past the 1000 ms a reload must stay under.
sleep 3
# qs skips a change that leaves the bytes the same, so a touch never reloads it.
echo "// reload 1" >>"$config/shell.qml"
# qs logs this once at start and once per reload, and status answers only after the reload's call returns.
loads() { journalctl --user -u "$DOTS_DEV_UNIT" --no-pager -o cat | grep -c 'Configuration Loaded'; }
reloaded() { (($(loads) >= 2)); }
check "the shell reloads" until_ok 5000 reloaded
until_ok 5000 first_frame >/dev/null
new=$(first_frame)
echo "     firstFrameMs before the reload: $old, after: $new"
check "firstFrameMs after a reload is below 1000" test "${new:-1000}" -lt 1000

exit $((fails > 0))
}
