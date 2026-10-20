#!/usr/bin/env bash
# Control's Wi-Fi section lists a fake NetworkManager's networks; Enter joins an open and a known network with no password, and a new secured one through a masked password line that takes a paste.
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
# Presses Enter on the row titled $1, or fails the check when that row cannot be selected.
enter_on() {
  if until_ok 3000 select_row "$1"; then wtype -k Return; else echo "FAIL the row $1 is listed and selected"; fails=$((fails + 1)); fi
}

# Quickshell's NetworkManager client talks to the system bus, which in the nested session is the nested session bus.
bus() { busctl --address="$DBUS_SESSION_BUS_ADDRESS" "$@"; }
nm=/org/freedesktop/NetworkManager
last_psk() { bus call org.freedesktop.NetworkManager "$nm" org.dots.FakeNM LastPsk 2>/dev/null; }
last_psk_is() { [ "$(last_psk)" = "s \"$1\"" ]; }

# The polkit prompt's password field is the look the Wi-Fi line copies, so its fake authority runs too.
polkit() { bus call org.freedesktop.PolicyKit1 /org/freedesktop/PolicyKit1/Authority org.dots.FakePolkit "$@"; }
pk_state() { timeout 0.5 qs ipc call polkit state 2>/dev/null; }
pk_is() { pk_state | jq -e "$1" >/dev/null 2>&1; }

DBUS_SYSTEM_BUS_ADDRESS=$DBUS_SESSION_BUS_ADDRESS "$repo/bin/dev-fake-networkmanager" &
fake_pid=$!
DBUS_SYSTEM_BUS_ADDRESS=$DBUS_SESSION_BUS_ADDRESS "$repo/bin/dev-fake-polkit" &
polkit_pid=$!
cleanup() { kill "$fake_pid" "$polkit_pid" 2>/dev/null; }
fake_up() { bus status org.freedesktop.NetworkManager >/dev/null 2>&1; }
until_ok 5000 fake_up
check "the NetworkManager double owns its name on the nested bus" fake_up
until_ok 3000 polkit Registered >/dev/null 2>&1
# Quickshell looks for NetworkManager once, when the shell starts, so the shell restarts to find the double.
systemctl --user restart "$DOTS_DEV_UNIT"
surfaces_mapped() { niri msg -j layers | jq -e 'any(.[]; .namespace == "dots-surfaces")' >/dev/null; }
until_ok 10000 surfaces_mapped
until_ok 5000 shell_status >/dev/null
until_ok 5000 pk_is .registered

control_focus() { niri msg -j layers | jq -e 'any(.[]; .namespace == "dots-surfaces" and .layer == "Overlay" and .keyboard_interactivity == "Exclusive")' >/dev/null; }
# Opens Control and tabs once, to Wi-Fi.
open_wifi() {
  niri msg action spawn -- qs ipc call control toggle
  until_ok 3000 section_is audio
  until_ok 3000 control_focus
  until_ok 3000 state_is '.keyboard'
  wtype -k Tab
  until_ok 2000 section_is wifi
}
open_wifi
check "Tab once is wifi" section_is wifi

three_rows() { state_is '.rows == ["Dots Home", "Dots Open", "Dots Secured"]'; }
until_ok 5000 three_rows
echo "     state: $(control_state | jq -c '{rows, details, selected}')"
check "Wi-Fi lists the known Dots Home, then Dots Open and Dots Secured by signal" three_rows
check "Dots Home reads known" detail_is "Dots Home" known
check "Dots Open reads its signal, 70%" detail_is "Dots Open" "70%"
check "Dots Secured reads its signal, 40%" detail_is "Dots Secured" "40%"

enter_on "Dots Open"
until_ok 3000 detail_is "Dots Open" connected
check "Enter on the open Dots Open connects it" detail_is "Dots Open" connected

enter_on "Dots Home"
until_ok 3000 detail_is "Dots Home" connected
check "Enter on the known Dots Home connects it" detail_is "Dots Home" connected
check "and Dots Open, saved by its join, reads known" detail_is "Dots Open" known
check "no password went to NetworkManager (LastPsk is empty)" last_psk_is ""
check "Enter on an open and on a known network opens no password line" state_is '.line == false and .pskLength == 0'

line_open() { state_is '.open and .section == "wifi" and .line == true'; }
no_line() { state_is '.open and .section == "wifi" and .line == false and .pskLength == 0 and .lineText == ""'; }
# Types $1 into the line and waits until the field holds that many characters.
type_psk() { wtype "$1"; until_ok 2000 state_is --argjson n "${#1}" '.pskLength == $n'; }
# Neither typed password ever shows in Control's state or the shell's journal.
state_clean() { ! control_state | grep -q -e dots-secret-1 -e nope; }
journal_clean() { ! journalctl --user -u "$DOTS_DEV_UNIT" --no-pager -o cat 2>/dev/null | grep -q -e dots-secret-1 -e nope; }

# Esc closes the line and leaves Control on Wi-Fi; j and k are letters of a password, not moves.
enter_on "Dots Secured"
until_ok 3000 line_open
check "Enter on the new secured Dots Secured opens the password line" line_open
row=$(control_state | jq .selected)
type_psk jk
check "the line takes j and k as letters, drawn as two dots ($(control_state | jq -c '{pskLength, lineText, selected}'))" \
  state_is --argjson r "$row" '.pskLength == 2 and .lineText == "••" and .selected == $r'
wtype -k Escape
until_ok 2000 no_line
check "Esc closes the line, empties it and leaves Control open on Wi-Fi" no_line
wtype -k Escape
until_ok 2000 state_is '.open == false'
check "a second Esc closes Control" state_is '.open == false'
open_wifi
check "Control reopens with no line and an empty field" no_line
# Closed any other way, Control clears the typed password at once, before its close stops drawing.
enter_on "Dots Secured"
until_ok 3000 line_open
type_psk ab
timeout 0.5 qs ipc call control toggle >/dev/null
check "closing Control by its toggle clears only the typed password while the card sinks ($(control_state | jq -c '{open, drawing, line, pskLength}'))" \
  state_is '.open == false and .drawing == true and .line == true and .pskLength == 0'
until_ok 2000 state_is '.open == false and .drawing == false'
open_wifi
check "Control reopens with no line and an empty field after a toggle close" no_line
# Backspace removes a whole character: an emoji is two UTF-16 units but one dot.
enter_on "Dots Secured"
until_ok 3000 line_open
wtype 🙂
until_ok 2000 state_is ".pskLength == 2"
wtype -k BackSpace
until_ok 2000 state_is '.pskLength == 0'
check "Backspace after an emoji leaves the field empty ($(control_state | jq -c '{pskLength, lineText}'))" state_is '.pskLength == 0 and .lineText == ""'
wtype a🙂
until_ok 2000 state_is ".pskLength == 3"
check "a then an emoji draw two dots ($(control_state | jq -c '{pskLength, lineText}'))" state_is '.lineText == "••"'
wtype -k Escape
until_ok 2000 no_line
wtype -k Escape
until_ok 2000 state_is '.open == false and .drawing == false'

# In each theme the line is drawn as the polkit prompt's password field, and a wrong password says so in the theme's voice.
look_keys='(.font | type == "string" and length > 0) and (.px | type == "number" and . > 0) and (.ink | type == "string") and (.border | type == "string") and (.placeholder | type == "string")'
same_look() { jq -e -n --argjson a "$1" --argjson b "$2" "\$a == \$b and (\$a | $look_keys)" >/dev/null 2>&1; }
status_theme() { shell_status | jq -e --arg t "$1" '.theme == $t' >/dev/null; }
in_theme() { "$repo/bin/dots" theme "$1" >/dev/null; until_ok 2000 status_theme "$1"; }
n=0
for t in "paper|WRONG PASSWORD|↵ JOIN · CTRL+V PASTE · ESC CANCEL|↵ CONNECT · D FORGET" "artboard|Wrong password|↵ join · ctrl+v paste · esc cancel|↵ connect · d forget" "blueprint|WRONG PASSWORD|↵ JOIN · CTRL+V PASTE · ESC CANCEL|↵ CONNECT · D FORGET"; do
  n=$((n + 1))
  IFS='|' read -r theme wrong join_hint connect_hint <<<"$t"
  in_theme "$theme"
  polkit Begin s "w$n" >/dev/null
  until_ok 3000 pk_is '.open and .settled'
  pk_look=$(pk_state | jq -c .fieldLook)
  wtype -k Escape
  until_ok 3000 pk_is '(.open | not) and .drawing == false'
  open_wifi
  enter_on "Dots Secured"
  until_ok 3000 line_open
  check "$theme: with the line open the hint reads $join_hint ($(control_state | jq -c .hint))" state_is --arg h "$join_hint" '.hint == $h'
  check "$theme: with the line open the legend drops tab, j/k and esc close ($(control_state | jq -c .legendDrawn))" state_is '.legendDrawn | ascii_downcase | gsub("[\\[\\]]"; "") == "↵ join  ctrl+v paste  esc cancel"'
  wifi_look=$(control_state | jq -c .lineLook)
  check "$theme: the line's field is drawn as the polkit field ($wifi_look, polkit $pk_look)" same_look "$wifi_look" "$pk_look"
  type_psk nope
  check "$theme: four typed characters draw four dots" state_is '.lineText == "••••"'
  check "$theme: and no state field holds the typed text" state_clean
  wtype -k Return
  until_ok 3000 state_is --arg m "$wrong" '.lineMessage == $m'
  check "$theme: a wrong password keeps the line open and empty and reads $wrong ($(control_state | jq -c '{line, pskLength, lineText, lineMessage}'))" \
    state_is --arg m "$wrong" '.line == true and .pskLength == 0 and .lineText == "" and .lineMessage == $m'
  wtype -k Escape
  until_ok 2000 no_line
  check "$theme: with the line closed the legend is back ($(control_state | jq -c .legendDrawn))" state_is '.legendDrawn | ascii_downcase | gsub("[\\[\\]]"; "") == "tab section  j/k move  esc close"'
  check "$theme: with the line closed the hint reads $connect_hint ($(control_state | jq -c .hint))" state_is --arg h "$connect_hint" '.hint == $h'
  wtype -k Escape
  until_ok 2000 state_is '.open == false and .drawing == false'
done

# A join that fails for another reason keeps the line open and says why; Quickshell names a lost network (53) and a supplicant timeout (11).
fail_next() { bus call org.freedesktop.NetworkManager "$nm" org.dots.FakeNM FailNext u "$1" >/dev/null; }
open_wifi
enter_on "Dots Secured"
until_ok 3000 line_open
for t in "53|network not found" "11|timed out" "10|could not join"; do
  IFS='|' read -r reason why <<<"$t"
  fail_next "$reason"
  type_psk dots-secret-1
  wtype -k Return
  until_ok 3000 state_is --arg m "$why" '(.lineMessage | ascii_downcase) == $m'
  check "a join that fails with device reason $reason keeps the line open and empty and reads $why ($(control_state | jq -c '{line, pskLength, lineMessage}'))" \
    state_is --arg m "$why" '.line == true and .pskLength == 0 and (.lineMessage | ascii_downcase) == $m'
done
wtype -k Escape
until_ok 2000 no_line
wtype -k Escape
until_ok 2000 state_is '.open == false and .drawing == false'

# A long passphrase can come from the clipboard: Ctrl+V adds its text, less the trailing newline a copy often carries.
open_wifi
enter_on "Dots Secured"
until_ok 3000 line_open
printf 'secret-1\n' | wl-copy
type_psk dots-
wtype -M ctrl v -m ctrl
until_ok 2000 state_is '.pskLength == 13'
check "the line draws dots- typed and secret-1 pasted as 13 dots ($(control_state | jq -c '{pskLength, lineText}'))" state_is '.lineText == "•••••••••••••"'
check "and no state field holds the typed text" state_clean
wtype -k Return
until_ok 3000 detail_is "Dots Secured" connected
echo "     state: $(control_state | jq -c '{rows, details, selected, line, lineMessage}')"
check "Enter on the line joins Dots Secured with the typed and pasted password" detail_is "Dots Secured" connected
check "and the double recorded that PSK" last_psk_is dots-secret-1
check "and the line closes" no_line
check "the shell's journal holds neither typed password" journal_clean

exit $((fails > 0))
}
