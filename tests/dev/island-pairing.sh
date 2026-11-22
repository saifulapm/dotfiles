#!/usr/bin/env bash
# A Bluetooth pairing request takes the island over as board 7's prompt: at rest a code to confirm draws at 30 px bold with Reject and an inverted Pair, and Enter pairs; over the launcher and over Control's Bluetooth page its chip names that surface, which comes back after; a PIN field takes digits and Esc rejects; a second request waits for the first; it draws over a fullscreen window; and one nobody answers leaves when the agent gives up.
{
source "$(dirname "$0")/lib.sh"

island() { timeout 0.5 qs ipc call island state 2>/dev/null; }
island_is() { island | jq -e "$@" >/dev/null 2>&1; }
pair() { timeout 0.5 qs ipc call pairing state 2>/dev/null; }
pair_is() { pair | jq -e "$@" >/dev/null 2>&1; }
launcher() { timeout 0.5 qs ipc call launcher state 2>/dev/null; }
launcher_is() { launcher | jq -e "$@" >/dev/null 2>&1; }
control() { timeout 0.5 qs ipc call control state 2>/dev/null; }
control_is() { control | jq -e "$@" >/dev/null 2>&1; }
open_launcher() {
  niri msg action spawn -- dots-call launcher toggle
  until_ok 3000 island_is '.surface == "launcher" and .animating == false'
  until_ok 2000 launcher_is '.keyboard and .settled'
}
open_bluetooth() {
  niri msg action spawn -- dots-call control section bluetooth
  until_ok 3000 island_is '.surface == "control" and .animating == false'
  until_ok 3000 control_is '.open and .section == "bluetooth" and .keyboard and .settled'
}
# Presses j until the row titled $1 is selected.
select_row() {
  local i n
  i=$(control | jq --arg t "$1" '.rows | index($t)')
  [ -n "$i" ] && [ "$i" != null ] || return 1
  for n in $(seq 12); do
    control_is --argjson i "$i" '.selected == $i' && return 0
    if control_is --argjson i "$i" '.selected < $i'; then wtype j; else wtype k; fi
    sleep 0.1
  done
  return 1
}
prompt_up() { island_is '.takeover == "pairing" and .animating == false' && pair_is '.open and .settled and .keyboard'; }
titled() { prompt_up && pair_is --arg t "$1" '.title == $t'; }
rest() { island_is '.surface == null and .takeover == null and .mode == "rest" and .animating == false'; }

# Quickshell's BlueZ client talks to the system bus, which in the nested session is the nested session bus.
bus() { busctl --address="$DBUS_SESSION_BUS_ADDRESS" "$@"; }
knob() { bus call org.bluez /org/bluez org.dots.FakeBluez "$@"; }
dev() { echo "/org/bluez/hci0/dev_00_00_00_00_00_0$1"; }
headphones=$(dev 2)
speaker=$(dev 3)
mouse=$(dev 4)
keyboard=$(dev 5)
prop_is() { [ "$(bus get-property org.bluez "$1" org.bluez.Device1 "$2" 2>/dev/null)" = "b $3" ]; }
# Device1.Pair as a BlueZ client calls it, and a service an untrusted device asks for; what BlueZ answered lands in a file.
pair_dev() { bus call --timeout=90 org.bluez "$1" org.bluez.Device1 Pair >"$DOTS_DEV_DIR/pair-$2" 2>&1 9>&- & }
authorize() { knob Authorize os "$1" 0000110d-0000-1000-8000-00805f9b34fb >"$DOTS_DEV_DIR/authorize-$2" 2>&1 9>&- & }
answered() { grep -q "$2" "$DOTS_DEV_DIR/$1"; }
start_agent() {
  DBUS_SYSTEM_BUS_ADDRESS=$DBUS_SESSION_BUS_ADDRESS DOTS_BT_AGENT_TIMEOUT_S=$1 "$repo/bin/dots-bt-agent" 9>&- &
  agent_pid=$!
}
registered() { (($(knob Calls | grep -o RequestDefaultAgent | wc -l) >= $1)); }

DBUS_SYSTEM_BUS_ADDRESS=$DBUS_SESSION_BUS_ADDRESS "$repo/bin/dev-fake-bluez" 9>&- &
fake_pid=$!
agent_pid=
cleanup() {
  kill "$agent_pid" "$fake_pid" 2>/dev/null
}
fake_up() { bus status org.bluez >/dev/null 2>&1; }
until_ok 5000 fake_up
# The shell restarts so Quickshell finds BlueZ as it starts, as it would at login.
systemctl --user restart "$DOTS_DEV_UNIT"
until_ok 10000 shell_status >/dev/null
start_agent 60
until_ok 5000 registered 1
until_ok 5000 rest

# At rest: a code to confirm.
knob SetPairing osu "$speaker" confirm 123456
pair_dev "$speaker" 1
until_ok 3000 prompt_up
check "a pairing request sets takeover to pairing ($(island | jq -c '{surface, takeover, mode}'))" island_is '.takeover == "pairing" and .surface == null'
check "the island is 520 px wide for it ($(island | jq .width))" island_is '.width == 520'
check "it draws 123456 at 30 px bold under Test Speaker ($(pair | jq -c '{title, code}'))" pair_is '.title == "Test Speaker" and .code.text == "123456" and .code.px == 30 and .code.bold'
check "with the Bluetooth glyph, no field and no chip ($(pair | jq -c '{glyph, field, chip}'))" pair_is '.glyph == 983215 and .field == null and .chip == null'
check "its buttons are Reject and an inverted Pair ($(pair | jq -c '[.buttons[] | [.text, .inverted]]'))" pair_is '[.buttons[] | [.text, .inverted]] == [["Reject", false], ["Pair", true]]'
check "island state reports it through no question slot ($(island | jq -c '{mode, ask}'))" island_is '.mode == "surface" and .ask == null and (has("pairing") | not)'
wtype -k Return
until_ok 3000 prop_is "$speaker" Paired true
check "Enter pairs Test Speaker (Paired true)" prop_is "$speaker" Paired true
until_ok 3000 rest
check "and the takeover ends on the resting island ($(island | jq -c '{surface, takeover, mode}'))" rest

# Over the launcher with fo typed.
open_launcher
wtype fo
until_ok 2000 launcher_is '.query == "fo"'
authorize "$headphones" 1
until_ok 3000 titled "Test Headphones"
check "over the launcher the chip reads Launcher and surface stays launcher ($(pair | jq -c .chip), $(island | jq -c '{surface, takeover}'))" eval 'pair_is ".chip == \"Launcher\"" && island_is ".surface == \"launcher\" and .takeover == \"pairing\""'
check "a service asked for reads wants Audio with Deny and an inverted Allow ($(pair | jq -c '{detail, buttons: [.buttons[] | [.text, .inverted]]}'))" pair_is '.detail == "wants Audio" and ([.buttons[] | [.text, .inverted]] == [["Deny", false], ["Allow", true]])'
wtype -k Return
until_ok 3000 answered authorize-1 allowed
check "Enter allows it" answered authorize-1 allowed
until_ok 3000 island_is '.takeover == null and .surface == "launcher" and .animating == false'
check "the launcher is back with fo ($(launcher | jq -c '{open, query}'))" launcher_is '.open and .query == "fo"'
until_ok 2000 launcher_is '.keyboard and .settled'
wtype o
until_ok 2000 launcher_is '.query == "foo"'
check "and has the keyboard: o makes foo ($(launcher | jq -c .query))" launcher_is '.query == "foo"'
wtype -k Escape
until_ok 3000 rest

# Over Control's Bluetooth page, as its Enter on a new device starts the pair.
open_bluetooth
wtype s
until_ok 3000 control_is '.rows | index("Test Keyboard") != null'
until_ok 3000 select_row "Test Keyboard"
wtype -k Return
until_ok 3000 titled "Test Keyboard"
check "over Control the chip reads Control ($(pair | jq -c .chip), $(island | jq -c '{surface, takeover}'))" eval 'pair_is ".chip == \"Control\"" && island_is ".surface == \"control\" and .takeover == \"pairing\""'
check "Control draws no pairing card of its own ($(control | jq -c .pairNote))" control_is '.pairNote == null'
# The power key opens Control's Power page, but not under a prompt (M7J9ETQA).
niri msg action spawn -- dots-call control section power
sleep 0.5
check "the power key under the prompt leaves Control on Bluetooth ($(control | jq -c .section), $(island | jq -c .takeover))" eval 'control_is ".section == \"bluetooth\"" && island_is ".takeover == \"pairing\""'
# The prompt, not Control, holds the keys, and the section call above opened nothing.
wtype -k Return # early on purpose
until_ok 3000 prop_is "$keyboard" Connected true
check "Enter pairs and connects Test Keyboard" prop_is "$keyboard" Connected true
until_ok 3000 island_is '.takeover == null and .surface == "control" and .animating == false'
check "Control is back on its Bluetooth page ($(control | jq -c '{open, section}'))" control_is '.open and .section == "bluetooth"'
until_ok 2000 control_is '.keyboard and .settled'

# A PIN asked while Control shows: the field takes digits, and Esc rejects.
knob SetPairing osu "$mouse" pin 0
pair_dev "$mouse" 2
until_ok 3000 titled "Test Mouse"
check "a PIN request draws a 44 px field reading PIN for Test Mouse ($(pair | jq -c '{detail, field}'))" pair_is '.detail == "asks for a PIN" and .field.h == 44 and .field.length == 0 and (.field.secret | not)'
wtype 0000
until_ok 2000 pair_is '.field.length == 4'
check "typing 0000 fills the field ($(pair | jq -c .field))" pair_is '.field.length == 4'
check "and none of it reaches Control ($(control | jq -c '{section, selected}'))" control_is '.open and .section == "bluetooth"'
wtype -k Escape
until_ok 3000 answered pair-2 org.bluez.Error.Rejected
check "Esc rejects, and BlueZ's Pair fails with the agent's no ($(cat "$DOTS_DEV_DIR/pair-2"))" answered pair-2 org.bluez.Error.Rejected
check "Test Mouse stays unpaired" prop_is "$mouse" Paired false
until_ok 3000 island_is '.takeover == null and .surface == "control" and .animating == false'
check "and Control is back on Bluetooth ($(control | jq -c '{open, section}'))" control_is '.open and .section == "bluetooth"'
until_ok 2000 control_is '.keyboard and .settled'
wtype -k Escape
until_ok 2000 control_is '.open and .section == "home"'
check "Control has the keyboard back: Esc returns it to Home ($(control | jq -c '{open, section}'))" control_is '.open and .section == "home"'
timeout 0.5 qs ipc call control close
until_ok 3000 rest

# A second request while one shows waits, and shows after the first.
authorize "$speaker" 2
until_ok 3000 titled "Test Speaker"
authorize "$headphones" 3
until_ok 2000 pair_is '.waiting == 1'
check "a second request waits behind the first ($(pair | jq -c '{title, waiting}'))" pair_is '.title == "Test Speaker" and .waiting == 1'
# A prompt ignores Enter for its first half second (29PTQZ0V), which the island's open no longer outlasts.
sleep 0.5
wtype -k Return
until_ok 3000 answered authorize-2 allowed
until_ok 3000 titled "Test Headphones"
check "once the first is answered the second shows ($(pair | jq -c '{title, waiting}'))" pair_is '.title == "Test Headphones" and .waiting == 0'
check "still as the island's takeover ($(island | jq -c '{takeover}'))" island_is '.takeover == "pairing"'
wtype -k Escape
until_ok 3000 answered authorize-3 org.bluez.Error.Rejected
check "Esc denies the second" answered authorize-3 org.bluez.Error.Rejected
until_ok 3000 rest

# Over a fullscreen window.
niri msg action spawn -- foot -c /dev/null sh -c 'sleep 600'
until_ok 5000 bash -c '[ "$(niri msg -j focused-window | jq -r .app_id)" = foot ]'
niri msg action fullscreen-window
until_ok 3000 island_is '.shown == false'
authorize "$speaker" 4
until_ok 3000 prompt_up
check "over a fullscreen window the prompt draws ($(island | jq -c '{shown, takeover, surface}'), $(pair | jq -c .chip))" island_is '.shown and .takeover == "pairing"'
wtype -k Escape
until_ok 3000 island_is '.takeover == null and .shown == false'
check "and after it the island hides again ($(island | jq -c '{shown, takeover, mode, surface}'))" island_is '.takeover == null and .shown == false'
niri msg action close-window

# Nobody answers: an agent that gives up in 4 s rejects it, and the launcher underneath is back.
kill "$agent_pid"
start_agent 4
until_ok 5000 registered 2
until_ok 3000 rest
open_launcher
wtype ti
until_ok 2000 launcher_is '.query == "ti"'
# The agent's 4 s start once it has the request, so the time from just before asking is at least 4 s.
asked_at=$(now_ms)
authorize "$speaker" 5
until_ok 3000 prompt_up
check "the prompt shows over the launcher ($(island | jq -c '{surface, takeover}'))" island_is '.surface == "launcher" and .takeover == "pairing"'
until_ok 8000 island_is '.takeover == null and .surface == "launcher" and .animating == false'
left=$(($(now_ms) - asked_at))
check "unanswered, the prompt leaves after the agent's 4 s ($left ms)" test "$left" -ge 4000
check "the agent rejected it" answered authorize-5 org.bluez.Error.Rejected
check "the launcher is back with ti ($(launcher | jq -c '{open, query}'))" launcher_is '.open and .query == "ti"'
until_ok 2000 launcher_is '.keyboard and .settled'
check "and has the keyboard" launcher_is '.keyboard'
wtype -k Escape

exit $((fails > 0))
}
