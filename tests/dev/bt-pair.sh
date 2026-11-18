#!/usr/bin/env bash
# Enter on a new device in Control's Bluetooth tab pairs, trusts and connects it through bin/dots-bt-agent, each request answered in the island's pairing prompt; Esc, a timeout or a failed pair leave it new and say Pairing failed.
{
source "$(dirname "$0")/lib.sh"

control_state() { timeout 0.5 qs ipc call control state 2>/dev/null; }
state_is() { control_state | jq -e "$@" >/dev/null 2>&1; }
section_is() { state_is --arg s "$1" '.open and .section == $s'; }
detail_is() { state_is --arg t "$1" --arg d "$2" '.details[.rows | index($t)] == $d'; }
island() { timeout 0.5 qs ipc call island state 2>/dev/null; }
island_is() { island | jq -e "$@" >/dev/null 2>&1; }
pair() { timeout 0.5 qs ipc call pairing state 2>/dev/null; }
pair_is() { pair | jq -e "$@" >/dev/null 2>&1; }
# A request takes the island over as the pairing prompt, whatever shows; it reads the device as its title and a detail, and holds the keyboard.
asks() { island_is '.takeover == "pairing"' && pair_is --arg t "$1" --arg d "$2" '.open and .settled and .keyboard and .title == $t and .detail == $d'; }
# A failed pair is the island's toast, or a line on Control's Bluetooth page while Control holds the island.
toast_is() { island_is --arg t "$1" '.mode == "toast" and .text == $t' || timeout 0.5 qs ipc call control state 2>/dev/null | jq -e --arg t "$1" '.open and .pairNote == $t' >/dev/null 2>&1; }
no_question() { ! island_is '.takeover == "pairing"' && ! pair_is '.open'; }
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
# Control opens on the Bluetooth page as Enter on its tile opens it.
open_bluetooth() {
  niri msg action spawn -- dots-call control section bluetooth
  until_ok 3000 section_is bluetooth
  until_ok 3000 control_focus
  until_ok 3000 state_is '.keyboard and .settled'
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

DBUS_SYSTEM_BUS_ADDRESS=$DBUS_SESSION_BUS_ADDRESS "$repo/bin/dev-fake-bluez" 9>&- &
fake_pid=$!
fake_up() { bus status org.bluez >/dev/null 2>&1; }
until_ok 5000 fake_up
# The shell restarts so Quickshell finds BlueZ as it starts, as it would at login.
systemctl --user restart "$DOTS_DEV_UNIT"
surfaces_mapped() { niri msg -j layers | jq -e 'any(.[]; .namespace == "dots-surfaces")' >/dev/null; }
until_ok 10000 surfaces_mapped
until_ok 5000 shell_status >/dev/null
# The agent asks the nested shell, by this session's WAYLAND_DISPLAY, and gives up on a request in 32 s rather than 60: past D-Bus's 25 s default, which once ended a pair early.
DBUS_SYSTEM_BUS_ADDRESS=$DBUS_SESSION_BUS_ADDRESS DOTS_BT_AGENT_TIMEOUT_S=32 "$repo/bin/dots-bt-agent" 9>&- &
agent_pid=$!
cleanup() {
  kill "$agent_pid" "$fake_pid" 2>/dev/null
}
registered() { knob Calls | grep -q RequestDefaultAgent; }
until_ok 5000 registered
check "dots-bt-agent registers as the default agent" registered

open_bluetooth
wtype s
until_ok 3000 state_is '.rows | index("Test Keyboard") != null'
check "a scan lists Test Keyboard" detail_is "Test Keyboard" new

# A code to confirm, answered from Control, which holds the keyboard.
until_ok 3000 select_row "Test Keyboard"
wtype -k Return
until_ok 3000 asks "Test Keyboard" "check this code shows on the device"
check "Enter on Test Keyboard asks to compare 123456 ($(pair | jq -c '{title, code: .code.text}'))" pair_is '.title == "Test Keyboard" and .code.text == "123456"'
check "the prompt draws Reject and Pair over Control ($(pair | jq -c '{chip, buttons: [.buttons[].text]}'))" pair_is '.chip == "Control" and [.buttons[].text] == ["Reject", "Pair"]'
# A person may take a while to compare the code: the answer still counts after D-Bus's 25 s default.
sleep 27
check "27 s on, the question still shows" asks "Test Keyboard" "check this code shows on the device"
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
until_ok 3000 asks "Test Phone" "check this code shows on the device"
check "Enter on Test Phone asks to compare 222222 ($(pair | jq -c .code.text))" pair_is '.title == "Test Phone" and .code.text == "222222"'
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
until_ok 3000 asks "Test Mouse" "type this on the device, then Enter"
check "a passkey to type draws 654321 for Test Mouse with Cancel alone ($(pair | jq -c '{code: .code.text, buttons: [.buttons[].text]}'))" pair_is '.code.text == "654321" and [.buttons[].text] == ["Cancel"]'
knob Typed o "$mouse"
until_ok 3000 prop_is "$mouse" Connected true
check "typed on the device, Test Mouse pairs and connects" prop_is "$mouse" Connected true
until_ok 3000 no_question
check "and the question goes" no_question
# A paired device connecting shows its 2 s connect state, which a toast waits behind.
no_connect() { ! island_is '.mode == "btConnect"'; }
until_ok 3000 no_connect

# A code typed wrong on the device fails the pair, and BlueZ sends no Cancel, so the shell drops the dead question itself.
knob SetPairing osu "$phone" display 111111
until_ok 3000 select_row "Test Phone"
wtype -k Return
until_ok 3000 asks "Test Phone" "type this on the device, then Enter"
check "a passkey to type draws 111111 for Test Phone ($(pair | jq -c .code.text))" pair_is '.code.text == "111111"'
knob Mistyped o "$phone"
until_ok 3000 toast_is "Pairing failed: Test Phone"
check "typed wrong on the device, the question goes and the island shows Pairing failed: Test Phone ($(island | jq -c '{mode, text}'))" toast_is "Pairing failed: Test Phone"
check "and Control's keys move again" state_is '.typing | not'

# A PIN typed in the island.
knob SetPairing osu "$phone" pin 0
until_ok 3000 select_row "Test Phone"
wtype -k Return
until_ok 3000 asks "Test Phone" "asks for a PIN"
check "a PIN request draws a field for Test Phone ($(pair | jq -c .field))" pair_is '.field.h == 44 and .field.length == 0'
wtype 0000
until_ok 2000 pair_is '.field.length == 4'
check "typing 0000 fills the prompt's field ($(pair | jq -c .field))" pair_is '.field.length == 4'
wtype -k Return
pin_sent() { knob Calls | grep -q "RequestPinCode $phone 0000"; }
until_ok 3000 pin_sent
check "Enter sends 0000 to BlueZ" pin_sent
until_ok 3000 prop_is "$phone" Paired true
check "and Test Phone pairs" prop_is "$phone" Paired true

# A service asked for by an untrusted device; the knob's answer is what the agent told BlueZ.
authorize() { knob Authorize os "$speaker" 0000110d-0000-1000-8000-00805f9b34fb >"$DOTS_DEV_DIR/authorize" 2>&1 9>&- & }
answered() { grep -q "$1" "$DOTS_DEV_DIR/authorize"; }
authorize
until_ok 3000 asks "Test Speaker" "wants Audio"
check "an untrusted Test Speaker asking for audio reads wants Audio" asks "Test Speaker" "wants Audio"
wtype -k Return
until_ok 3000 answered allowed
check "Enter allows it" answered allowed
authorize
until_ok 3000 asks "Test Speaker" "wants Audio"
wtype -k Escape
until_ok 3000 answered org.bluez.Error.Rejected
check "Esc denies it" answered org.bluez.Error.Rejected

# Do Not Disturb never hides a pairing request, and with Control closed the prompt takes the keyboard itself.
until_ok 3000 no_question
timeout 0.5 qs ipc call control close
until_ok 3000 state_is '.open == false'
timeout 0.5 qs ipc call notifs dnd true
dnd_on() { timeout 0.5 qs ipc call notifs state 2>/dev/null | jq -e '.dnd == true' >/dev/null; }
until_ok 2000 dnd_on
authorize
until_ok 3000 asks "Test Speaker" "wants Audio"
check "with Do Not Disturb on the prompt still shows, with no chip ($(pair | jq -c .chip))" eval 'asks "Test Speaker" "wants Audio" && pair_is ".chip == null"'
wtype -k Return
until_ok 3000 answered allowed
check "with Control closed, Enter allows it" answered allowed
timeout 0.5 qs ipc call notifs dnd false

# Left unanswered, the agent gives up and the island says the pair failed.
open_bluetooth
wtype s
until_ok 3000 state_is '.rows | index("00:00:00:00:00:07") != null'
knob SetPairing osu "$nameless" confirm 333333
until_ok 3000 select_row "00:00:00:00:00:07"
wtype -k Return
until_ok 3000 asks "00:00:00:00:00:07" "check this code shows on the device"
check "the nameless device asks by its address ($(pair | jq -c '{title, code: .code.text}'))" pair_is '.title == "00:00:00:00:00:07" and .code.text == "333333"'
until_ok 36000 toast_is "Pairing failed: 00:00:00:00:00:07"
check "left 32 s, the island shows Pairing failed: 00:00:00:00:00:07 ($(island | jq -c '{mode, text}'))" toast_is "Pairing failed: 00:00:00:00:00:07"
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

# Only the agent writes the socket, so a line BlueZ would never cause is refused, not drawn.
forged=$(printf '%s\n' '{"kind":"confirm","device":"","address":"","code":"123456","service":""}' | timeout 2 socat - "UNIX-CONNECT:$XDG_RUNTIME_DIR/dots-bt-$WAYLAND_DISPLAY.sock")
check "a forged request naming no device is answered no ($forged)" test "$forged" = '{"ok":false}'
check "and the island asks nothing" no_question

exit $((fails > 0))
}
