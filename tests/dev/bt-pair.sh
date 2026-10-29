#!/usr/bin/env bash
# Enter on a new device in Control's Bluetooth tab pairs, trusts and connects it through bin/dots-bt-agent, each request answered in the island; Esc, a timeout or a failed pair leave it new and say Pairing failed.
{
source "$(dirname "$0")/lib.sh"

control_state() { timeout 0.5 qs ipc call control state 2>/dev/null; }
state_is() { control_state | jq -e "$@" >/dev/null 2>&1; }
section_is() { state_is --arg s "$1" '.open and .section == $s'; }
detail_is() { state_is --arg t "$1" --arg d "$2" '.details[.rows | index($t)] == $d'; }
island() { timeout 0.5 qs ipc call island state 2>/dev/null; }
island_is() { island | jq -e "$@" >/dev/null 2>&1; }
asks() { island_is --arg t "$1" '.mode == "question" and .text == $t'; }
toast_is() { island_is --arg t "$1" '.mode == "toast" and .text == $t'; }
no_question() { ! island_is '.mode == "question"'; }
# Presses j until the row titled $1 is selected.
select_row() {
  local i n
  i=$(control_state | jq --arg t "$1" '.rows | index($t)')
  [ -n "$i" ] && [ "$i" != null ] || return 1
  for n in $(seq 12); do
    state_is --argjson i "$i" '.selected == $i' && return 0
    if state_is --argjson i "$i" '.selected < $i'; then wtype j; else wtype k; fi
    sleep 0.1
  done
  return 1
}
control_focus() { niri msg -j layers | jq -e 'any(.[]; .namespace == "dots-surfaces" and .layer == "Overlay" and .keyboard_interactivity == "Exclusive")' >/dev/null; }
section_not() { ! section_is "$1"; }
tab_to() {
  local n s
  until_ok 3000 state_is '.keyboard' || return 1
  for n in 1 2 3 4 5 6; do
    section_is "$1" && return 0
    s=$(control_state | jq -r .section)
    wtype -k Tab
    until_ok 2000 section_not "$s" || return 1
  done
  section_is "$1"
}

# Quickshell's BlueZ client talks to the system bus, which in the nested session is the nested session bus.
bus() { busctl --address="$DBUS_SESSION_BUS_ADDRESS" "$@"; }
knob() { bus call org.bluez /org/bluez org.dots.FakeBluez "$@"; }
dev() { echo "/org/bluez/hci0/dev_00_00_00_00_00_0$1"; }
keyboard=$(dev 5)
mouse=$(dev 4)
phone=$(dev 6)
speaker=$(dev 3)
nameless=$(dev 7)
prop_is() { [ "$(bus get-property org.bluez "$1" org.bluez.Device1 "$2" 2>/dev/null)" = "b $3" ]; }

DBUS_SYSTEM_BUS_ADDRESS=$DBUS_SESSION_BUS_ADDRESS "$repo/bin/dev-fake-bluez" &
fake_pid=$!
fake_up() { bus status org.bluez >/dev/null 2>&1; }
until_ok 5000 fake_up
# The shell restarts so Quickshell finds BlueZ as it starts, as it would at login.
systemctl --user restart "$DOTS_DEV_UNIT"
surfaces_mapped() { niri msg -j layers | jq -e 'any(.[]; .namespace == "dots-surfaces")' >/dev/null; }
until_ok 10000 surfaces_mapped
until_ok 5000 shell_status >/dev/null
# The agent asks the nested shell, by this session's WAYLAND_DISPLAY, and gives up on a request in 4 s rather than 60.
DBUS_SYSTEM_BUS_ADDRESS=$DBUS_SESSION_BUS_ADDRESS DOTS_BT_AGENT_TIMEOUT_S=4 "$repo/bin/dots-bt-agent" &
agent_pid=$!
cleanup() {
  kill "$agent_pid" "$fake_pid" 2>/dev/null
}
registered() { knob Calls | grep -q RequestDefaultAgent; }
until_ok 5000 registered
check "dots-bt-agent registers as the default agent" registered

niri msg action spawn -- dots-call control toggle
until_ok 3000 section_is audio
until_ok 3000 control_focus
tab_to bluetooth
wtype s
until_ok 3000 state_is '.rows | index("Test Keyboard") != null'
check "a scan lists Test Keyboard" detail_is "Test Keyboard" new

# A code to confirm, answered from Control, which holds the keyboard.
until_ok 3000 select_row "Test Keyboard"
wtype -k Return
until_ok 3000 asks "Pair Test Keyboard? 123456"
check "Enter on Test Keyboard asks Pair Test Keyboard? 123456 ($(island | jq -c '{mode, text}'))" asks "Pair Test Keyboard? 123456"
check "the island names its keys, ↵ yes and esc no" island_is '.pairing.keys == ["↵ yes", "esc no"]'
check "Control's legend names them too ($(control_state | jq -c .legend))" state_is '.legend | ascii_downcase | contains("yes") and contains("no")'
wtype -k Return
until_ok 3000 prop_is "$keyboard" Connected true
check "Enter pairs it (Paired true)" prop_is "$keyboard" Paired true
check "trusts it (Trusted true)" prop_is "$keyboard" Trusted true
check "and connects it (Connected true)" prop_is "$keyboard" Connected true
until_ok 2000 detail_is "Test Keyboard" "connected · trusted"
check "its row reads connected · trusted" detail_is "Test Keyboard" "connected · trusted"
check "and the question is gone" no_question

# Esc says no.
until_ok 3000 select_row "Test Phone"
wtype -k Return
until_ok 3000 asks "Pair Test Phone? 222222"
check "Enter on Test Phone asks Pair Test Phone? 222222" asks "Pair Test Phone? 222222"
wtype -k Escape
until_ok 3000 no_question
check "Esc puts the question away" no_question
check "Control stays open on Bluetooth" section_is bluetooth
check "Test Phone stays unpaired" prop_is "$phone" Paired false
until_ok 2000 detail_is "Test Phone" new
check "and its row reads new" detail_is "Test Phone" new

# A passkey shown for typing on the device; the device types it.
knob SetPairing osu "$mouse" display 654321
until_ok 3000 select_row "Test Mouse"
wtype -k Return
until_ok 3000 asks "Type 654321 on Test Mouse"
check "a passkey to type reads Type 654321 on Test Mouse" asks "Type 654321 on Test Mouse"
knob Typed o "$mouse"
until_ok 3000 prop_is "$mouse" Connected true
check "typed on the device, Test Mouse pairs and connects" prop_is "$mouse" Connected true
until_ok 3000 no_question
check "and the question goes" no_question

# A code typed wrong on the device fails the pair, and BlueZ sends no Cancel, so the shell drops the dead question itself.
knob SetPairing osu "$phone" display 111111
until_ok 3000 select_row "Test Phone"
wtype -k Return
until_ok 3000 asks "Type 111111 on Test Phone"
check "a passkey to type reads Type 111111 on Test Phone" asks "Type 111111 on Test Phone"
knob Mistyped o "$phone"
until_ok 3000 toast_is "Pairing failed: Test Phone"
check "typed wrong on the device, the question goes and the island shows Pairing failed: Test Phone ($(island | jq -c '{mode, text}'))" toast_is "Pairing failed: Test Phone"
check "and Control's keys move again" state_is '.legend | ascii_downcase | contains("move")'

# A PIN typed in the island.
knob SetPairing osu "$phone" pin 0
until_ok 3000 select_row "Test Phone"
wtype -k Return
until_ok 3000 asks "PIN for Test Phone"
check "a PIN request reads PIN for Test Phone" asks "PIN for Test Phone"
wtype 0000
until_ok 2000 island_is '.pairing.pin == "0000"'
check "typing 0000 shows it in the island" island_is '.pairing.pin == "0000"'
wtype -k Return
pin_sent() { knob Calls | grep -q "RequestPinCode $phone 0000"; }
until_ok 3000 pin_sent
check "Enter sends 0000 to BlueZ" pin_sent
until_ok 3000 prop_is "$phone" Paired true
check "and Test Phone pairs" prop_is "$phone" Paired true

# A service asked for by an untrusted device; the knob's answer is what the agent told BlueZ.
authorize() { knob Authorize os "$speaker" 0000110d-0000-1000-8000-00805f9b34fb >"$DOTS_DEV_DIR/authorize" 2>&1 & }
answered() { grep -q "$1" "$DOTS_DEV_DIR/authorize"; }
authorize
until_ok 3000 asks "Test Speaker wants Audio"
check "an untrusted Test Speaker asking for audio reads Test Speaker wants Audio" asks "Test Speaker wants Audio"
wtype -k Return
until_ok 3000 answered allowed
check "Enter allows it" answered allowed
authorize
until_ok 3000 asks "Test Speaker wants Audio"
wtype -k Escape
until_ok 3000 answered org.bluez.Error.Rejected
check "Esc denies it" answered org.bluez.Error.Rejected

# Do Not Disturb never hides a pairing question, and with Control closed Mod+I answers it.
wtype -k Escape
until_ok 3000 state_is '.open == false'
timeout 0.5 qs ipc call notifs dnd true
dnd_on() { timeout 0.5 qs ipc call notifs state 2>/dev/null | jq -e '.dnd == true' >/dev/null; }
until_ok 2000 dnd_on
authorize
until_ok 3000 asks "Test Speaker wants Audio"
check "with Do Not Disturb on the question still shows" asks "Test Speaker wants Audio"
timeout 0.5 qs ipc call island focus
until_ok 2000 island_is '.focused'
wtype -k Return
until_ok 3000 answered allowed
check "with Control closed, Mod+I then Enter allows it" answered allowed
timeout 0.5 qs ipc call notifs dnd false

# Left unanswered, the agent gives up and the island says the pair failed.
niri msg action spawn -- dots-call control toggle
until_ok 3000 section_is audio
until_ok 3000 control_focus
tab_to bluetooth
wtype s
until_ok 3000 state_is '.rows | index("00:00:00:00:00:07") != null'
knob SetPairing osu "$nameless" confirm 333333
until_ok 3000 select_row "00:00:00:00:00:07"
wtype -k Return
until_ok 3000 asks "Pair 00:00:00:00:00:07? 333333"
check "the nameless device asks by its address" asks "Pair 00:00:00:00:00:07? 333333"
until_ok 6000 toast_is "Pairing failed: 00:00:00:00:00:07"
check "left 4 s, the island shows Pairing failed: 00:00:00:00:00:07 ($(island | jq -c '{mode, text}'))" toast_is "Pairing failed: 00:00:00:00:00:07"
check "and the device stays unpaired" prop_is "$nameless" Paired false
gone_in_2s() { until_ok 2500 no_toast; }
no_toast() { ! island_is '.mode == "toast"'; }
check "the toast goes after its 1.5 s" gone_in_2s

# A pair BlueZ fails says the same.
knob SetPairing osu "$speaker" fail 0
until_ok 3000 select_row "Test Speaker"
wtype -k Return
until_ok 3000 toast_is "Pairing failed: Test Speaker"
check "a failed pair shows Pairing failed: Test Speaker" toast_is "Pairing failed: Test Speaker"
until_ok 2000 detail_is "Test Speaker" new
check "and Test Speaker reads new" detail_is "Test Speaker" new

exit $((fails > 0))
}
