#!/usr/bin/env bash
# A hot reload keeps Quickshell's BlueZ devices, so the new tree reads them at once, and the first connect after it still shows its connect state.
{
repo=$(cd "$(dirname "$0")/../.." && pwd)
# The nested shell runs a copy, so this check's edit never reaches the shell/ the live shell watches.
copy=$(mktemp -d)
cp -a "$repo/shell" "$copy/shell"
# The shell runs ../bin helpers from its own dir.
ln -s "$repo/bin" "$copy/bin"
export DOTS_DEV_SHELL=$copy/shell
source "$(dirname "$0")/lib.sh"

island() { timeout 0.5 qs ipc call island state 2>/dev/null; }
mode_is() { island | jq -e --arg m "$1" '.mode == $m' >/dev/null 2>&1; }
bus() { busctl --address="$DBUS_SESSION_BUS_ADDRESS" "$@"; }
headphones=/org/bluez/hci0/dev_00_00_00_00_00_02

DBUS_SYSTEM_BUS_ADDRESS=$DBUS_SESSION_BUS_ADDRESS "$repo/bin/dev-fake-bluez" &
fake_pid=$!
cleanup() {
  bus call org.bluez "$headphones" org.bluez.Device1 Disconnect 2>/dev/null
  kill "$fake_pid" 2>/dev/null
  rm -rf "$copy"
}
fake_up() { bus status org.bluez >/dev/null 2>&1; }
until_ok 5000 fake_up
systemctl --user restart "$DOTS_DEV_UNIT"
until_ok 10000 shell_status >/dev/null
pid=$(systemctl --user show -p MainPID --value "$DOTS_DEV_UNIT")
config=$(tr '\0' '\n' <"/proc/$pid/environ" | sed -n 's/^QS_CONFIG_PATH=//p')
check "the nested shell runs a copy, not $repo/shell" test -n "$config" -a "$config" != "$repo/shell"
at_rest() { shell_status | jq -e '.timers == 1' >/dev/null 2>&1 && mode_is rest; }
until_ok 6000 at_rest

# qs skips a change that leaves the bytes the same, so a touch never reloads it.
echo "// reload 1" >>"$config/shell.qml"
loads() { journalctl --user -u "$DOTS_DEV_UNIT" --no-pager -o cat | grep -c 'Configuration Loaded'; }
reloaded() { (($(loads) >= 2)); }
check "the shell reloads" until_ok 5000 reloaded
until_ok 5000 shell_status >/dev/null
until_ok 6000 at_rest

bus call org.bluez "$headphones" org.bluez.Device1 Connect
until_ok 2000 mode_is btConnect
check "the first connect after a reload shows its connect state ($(island | jq -c '{mode, text}'))" mode_is btConnect
exit $((fails > 0))
}
