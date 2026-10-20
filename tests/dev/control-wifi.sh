#!/usr/bin/env bash
# Control's Wi-Fi section lists a fake NetworkManager's networks; Enter joins an open and a known network with no password.
{
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

# Quickshell's NetworkManager client talks to the system bus, which in the nested session is the nested session bus.
bus() { busctl --address="$DBUS_SESSION_BUS_ADDRESS" "$@"; }
nm=/org/freedesktop/NetworkManager
wlan0=$nm/Devices/1
secured_ap=$nm/AccessPoint/3
last_psk() { bus call org.freedesktop.NetworkManager "$nm" org.dots.FakeNM LastPsk 2>/dev/null; }
last_psk_is() { [ "$(last_psk)" = "s \"$1\"" ]; }

DBUS_SYSTEM_BUS_ADDRESS=$DBUS_SESSION_BUS_ADDRESS "$repo/bin/dev-fake-networkmanager" &
fake_pid=$!
cleanup() { kill "$fake_pid" 2>/dev/null; }
fake_up() { bus status org.freedesktop.NetworkManager >/dev/null 2>&1; }
until_ok 5000 fake_up
check "the NetworkManager double owns its name on the nested bus" fake_up
# Quickshell looks for NetworkManager once, when the shell starts, so the shell restarts to find the double.
systemctl --user restart "$DOTS_DEV_UNIT"
surfaces_mapped() { niri msg -j layers | jq -e 'any(.[]; .namespace == "dots-surfaces")' >/dev/null; }
until_ok 10000 surfaces_mapped
until_ok 5000 shell_status >/dev/null

niri msg action spawn -- qs ipc call control toggle
control_focus() { niri msg -j layers | jq -e 'any(.[]; .namespace == "dots-surfaces" and .layer == "Overlay" and .keyboard_interactivity == "Exclusive")' >/dev/null; }
until_ok 3000 section_is audio
until_ok 3000 control_focus
until_ok 3000 state_is '.keyboard'
wtype -k Tab
until_ok 2000 section_is wifi
check "Tab once is wifi" section_is wifi

three_rows() { state_is '.rows == ["Dots Home", "Dots Open", "Dots Secured"]'; }
until_ok 5000 three_rows
echo "     state: $(control_state | jq -c '{rows, details, selected}')"
check "Wi-Fi lists the known Dots Home, then Dots Open and Dots Secured by signal" three_rows
check "Dots Home reads known" detail_is "Dots Home" known
check "Dots Open reads its signal, 70%" detail_is "Dots Open" "70%"
check "Dots Secured reads its signal, 40%" detail_is "Dots Secured" "40%"

until_ok 3000 select_row "Dots Open"
wtype -k Return
until_ok 3000 detail_is "Dots Open" connected
check "Enter on the open Dots Open connects it" detail_is "Dots Open" connected

until_ok 3000 select_row "Dots Home"
wtype -k Return
until_ok 3000 detail_is "Dots Home" connected
check "Enter on the known Dots Home connects it" detail_is "Dots Home" connected
check "and Dots Open, saved by its join, reads known" detail_is "Dots Open" known
check "no password went to NetworkManager (LastPsk is empty)" last_psk_is ""

# The UI cannot type a password yet, so this drives the double directly, the way connectWithPsk calls it.
bus call org.freedesktop.NetworkManager "$nm" org.freedesktop.NetworkManager AddAndActivateConnection 'a{sa{sv}}oo' \
  1 802-11-wireless-security 1 psk s dots-secret-1 "$wlan0" "$secured_ap" >/dev/null
until_ok 3000 detail_is "Dots Secured" connected
echo "     state: $(control_state | jq -c '{rows, details, selected}')"
check "a join of Dots Secured with the right PSK connects it" detail_is "Dots Secured" connected
check "and the double recorded that PSK" last_psk_is dots-secret-1

exit $((fails > 0))
}
