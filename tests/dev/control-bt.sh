#!/usr/bin/env bash
# Control's Bluetooth section lists a fake BlueZ's devices; Enter connects and disconnects, d forgets.
source "$(dirname "$0")/lib.sh"

control_state() { timeout 0.5 qs ipc call control state 2>/dev/null; }
state_is() { control_state | jq -e "$@" >/dev/null 2>&1; }
section_is() { state_is --arg s "$1" '.open and .section == $s'; }
detail_is() { state_is --arg t "$1" --arg d "$2" '.details[.rows | index($t)] == $d'; }
# Presses j until the row titled $1 is selected.
select_row() {
  local i n
  i=$(control_state | jq --arg t "$1" '.rows | index($t)')
  [ -n "$i" ] && [ "$i" != null ] || return 1
  for n in 1 2 3 4 5 6 7 8; do
    state_is --argjson i "$i" '.selected == $i' && return 0
    if state_is --argjson i "$i" '.selected < $i'; then wtype j; else wtype k; fi
    sleep 0.1
  done
  return 1
}

# Quickshell's BlueZ client talks to the system bus, which in the nested session is the nested session bus.
bus() { busctl --address="$DBUS_SESSION_BUS_ADDRESS" "$@"; }
headphones=/org/bluez/hci0/dev_00_00_00_00_00_02
speaker=/org/bluez/hci0/dev_00_00_00_00_00_03
connected_is() { [ "$(bus get-property org.bluez "$headphones" org.bluez.Device1 Connected 2>/dev/null)" = "b $1" ]; }

DBUS_SYSTEM_BUS_ADDRESS=$DBUS_SESSION_BUS_ADDRESS "$repo/bin/dev-fake-bluez" &
fake_pid=$!
cleanup() {
  bus call org.bluez "$headphones" org.bluez.Device1 Disconnect 2>/dev/null
  kill "$fake_pid" 2>/dev/null
}
fake_up() { bus status org.bluez >/dev/null 2>&1; }
until_ok 5000 fake_up
check "the BlueZ double owns org.bluez on the nested bus" fake_up
# The shell restarts so Quickshell finds BlueZ as it starts, as it would at login.
systemctl --user restart "$DOTS_DEV_UNIT"
surfaces_mapped() { niri msg -j layers | jq -e 'any(.[]; .namespace == "dots-surfaces")' >/dev/null; }
until_ok 10000 surfaces_mapped
until_ok 5000 shell_status >/dev/null

niri msg action spawn -- qs ipc call control toggle
control_focus() { niri msg -j layers | jq -e 'any(.[]; .namespace == "dots-surfaces" and .layer == "Overlay" and .keyboard_interactivity == "Exclusive")' >/dev/null; }
until_ok 3000 section_is audio
until_ok 3000 control_focus
# The first Tab can reach the layer before it has the keyboard, so Tab repeats until the section moves.
tab_to() { local n; for n in 1 2 3 4 5 6; do section_is "$1" && return 0; wtype -k Tab; sleep 0.15; done; section_is "$1"; }
tab_to bluetooth
check "Tab twice is bluetooth" section_is bluetooth
until_ok 3000 detail_is "Test Headphones" paired
echo "     state: $(control_state)"
check "Test Headphones reads paired" detail_is "Test Headphones" paired
check "Test Speaker reads new" detail_is "Test Speaker" new

until_ok 3000 select_row "Test Headphones"
wtype -k Return
until_ok 3000 connected_is true
check "Enter connects Test Headphones (BlueZ reports Connected true)" connected_is true
until_ok 2000 detail_is "Test Headphones" connected
check "its row reads connected" detail_is "Test Headphones" connected

until_ok 3000 select_row "Test Headphones"
wtype -k Return
until_ok 3000 connected_is false
check "Enter again disconnects it" connected_is false
until_ok 2000 detail_is "Test Headphones" paired
check "its row reads paired again" detail_is "Test Headphones" paired

# Connecting moves a device to the top, and the selection goes with it.
until_ok 3000 select_row "Test Speaker"
wtype -k Return
until_ok 3000 bash -c "busctl --address=\"$DBUS_SESSION_BUS_ADDRESS\" get-property org.bluez $speaker org.bluez.Device1 Connected | grep -q true"
until_ok 2000 detail_is "Test Speaker" connected
on_speaker() { state_is '.rows[.selected] == "Test Speaker"'; }
check "the selection stays on Test Speaker as it moves to the top" on_speaker
wtype -k Return
until_ok 2000 detail_is "Test Speaker" new
check "so Enter again disconnects Test Speaker, not Test Headphones" detail_is "Test Speaker" new

until_ok 3000 select_row "Test Speaker"
wtype d
speaker_gone() { ! bus get-property org.bluez "$speaker" org.bluez.Device1 Address >/dev/null 2>&1; }
until_ok 3000 speaker_gone
check "d on Test Speaker removes it from BlueZ" speaker_gone
until_ok 2000 state_is '.rows | index("Test Speaker") == null'
check "its row goes" state_is '.rows | index("Test Speaker") == null'
echo "     state: $(control_state)"

exit $((fails > 0))
