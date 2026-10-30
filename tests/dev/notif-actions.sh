#!/usr/bin/env bash
# A notification's actions as chips on the island card: Mod+I, then 1 to 9 runs the action with that number.
{
source "$(dirname "$0")/lib.sh"
out=$(mktemp)
cleanup() { rm -f "$out"; }

until_ok 5000 shell_status >/dev/null
island() { timeout 0.5 qs ipc call island state 2>/dev/null; }
mode_is() { island | jq -e --arg m "$1" '.mode == $m' >/dev/null 2>&1; }
shows() { island | jq -e --arg s "$1" '.mode == "notification" and (.note.summary | ascii_downcase) == $s' >/dev/null 2>&1; }
island_focus() { niri msg -j layers | jq -e --arg k "$1" 'any(.[]; .namespace == "dots-island" and .keyboard_interactivity == $k)' >/dev/null; }
mod_i() {
  niri msg action spawn -- dots-call island focus
  until_ok 2000 island_focus Exclusive
}
# Each theme writes a key its own way (1, [1]) and a word in caps or not, so the chips are read as "1 yes".
chips() { island | jq -c '[.note.actions[] | ascii_downcase | gsub("[\\[\\]]"; "")]'; }
chips_are() { [ "$(chips)" = "$1" ]; }
printed() { [ "$(cat "$out")" = "$1" ]; }
# notify-send -A waits for an action or the close, and prints the action's key; it is let go at the end of each step.
ask() { notify-send -a T "$@" >"$out" & sender=$!; }
done_asking() {
  [ -z "$sender" ] || kill "$sender" 2>/dev/null
  wait "$sender" 2>/dev/null
  timeout 0.5 qs ipc call notifs clear >/dev/null
  until_ok 2000 mode_is rest
  : >"$out"
}

ask -A yes=Yes -A no=No ask
until_ok 2000 shows ask
check "two actions draw two chips ($(chips))" chips_are '["1 yes","2 no"]'
mod_i
wtype -k 2
until_ok 2000 printed no
check "Mod+I, 2: notify-send prints no ($(cat "$out"))" printed no
check "and the card leaves" until_ok 2000 mode_is rest
done_asking

ask -A a=One -A b=Two -A c=Three -A d=Four -A e=Five five
until_ok 2000 shows five
check "five actions draw three chips ($(chips))" chips_are '["1 one","2 two","3 three"]'
mod_i
wtype -k 4
sleep 1
check "4 runs nothing" printed ""
check "and the card stays" shows five
done_asking

ask -A default=Open -A settings=Settings -A later=Later web
until_ok 2000 shows web
check "default and settings draw no chip ($(chips))" chips_are '["1 later"]'
mod_i
wtype -k Return
until_ok 2000 printed default
check "Enter runs the default action ($(cat "$out"))" printed default
done_asking

# notify-send closes its notification as it exits after an action, so the resident one comes from gdbus, and the bus shows the action.
gdbus monitor --session --dest org.freedesktop.Notifications >"$out" &
monitor=$!
gdbus call --session --dest org.freedesktop.Notifications --object-path /org/freedesktop/Notifications \
  --method org.freedesktop.Notifications.Notify T 0 "" stay "" '["yes", "Yes"]' '{"resident": <true>}' 0 >/dev/null
until_ok 2000 shows stay
mod_i
wtype -k 1
invoked() { grep -q "ActionInvoked (uint32 [0-9]*, 'yes')" "$out"; }
check "1 on a resident notification invokes yes" until_ok 2000 invoked
sleep 0.5
check "and its card stays" shows stay
kill "$monitor"
wait "$monitor" 2>/dev/null
sender=
done_asking

ask -A yes=Yes -A no=No away
until_ok 2000 shows away
check "with the island not focused" island_focus None
wtype -k 2
sleep 1
check "2 prints nothing" printed ""
done_asking

# Mod+A's selected row draws the same chips while the app holds its notification, and the same keys run them.
notifs() { timeout 0.5 qs ipc call notifs state 2>/dev/null; }
centre_is() { notifs | jq -e "$@" >/dev/null; }
centre_focus() { niri msg -j layers | jq -e --arg k "$1" 'any(.[]; .namespace == "dots-surfaces" and .layer == "Overlay" and .keyboard_interactivity == $k)' >/dev/null; }
open_centre() {
  niri msg action spawn -- dots-call notifs open
  until_ok 3000 centre_is .open
  until_ok 2000 centre_focus Exclusive
}
close_centre() {
  niri msg action spawn -- dots-call notifs close
  until_ok 2000 centre_is '.open == false'
}
row_chips() { notifs | jq -c '[.actions[] | [.[] | ascii_downcase | gsub("[\\[\\]]"; "")]]'; }
legend() { notifs | jq -r '.legend | ascii_downcase | gsub("[\\[\\]]"; "")'; }
legend_has() { [[ "$(legend)" == *"$1"* ]]; }

notify-send -a T -A old=Old older >/dev/null &
older=$!
until_ok 2000 shows older
ask -A yes=Yes -A no=No newer
until_ok 2000 shows newer
open_centre
check "the selected row draws its chips and the other none ($(row_chips))" test "$(row_chips)" = '[["1 yes","2 no"],[]]'
check "the legend names 1-3 action ($(legend))" legend_has "1-3 action"
wtype -k 1
until_ok 2000 printed yes
check "1 on the row prints yes ($(cat "$out"))" printed yes
check "and the centre closes" until_ok 2000 centre_is '.open == false'
kill "$older"
done_asking

ask -A yes=Yes gone
until_ok 2000 shows gone
kill "$sender"
wait "$sender" 2>/dev/null
sender=
open_centre
wtype -k 1
sleep 1
check "1 on the row of a killed sender prints nothing" printed ""
check "and the shell keeps running" shell_status
close_centre
done_asking

notify-send -a T -A yes=Yes kept >/dev/null &
sender=$!
until_ok 2000 shows kept
systemctl --user restart "$DOTS_DEV_UNIT"
until_ok 5000 at_rest
open_centre
check "after a shell restart its row draws no chips ($(row_chips))" test "$(row_chips)" = '[[]]'
close_centre
done_asking

# Each theme's chips stand out from what they sit on: the island's dark card, and Mod+A's cursor row.
status_theme() { shell_status | jq -e --arg t "$1" '.theme == $t and .transition == ""' >/dev/null; }
apart() { jq -e 'map(ascii_downcase) | .[0] != .[2] and .[1] != .[2]' >/dev/null <<<"$1"; }
for t in paper artboard blueprint; do
  "$repo/bin/dots" theme "$t" >/dev/null
  until_ok 8000 status_theme "$t"
  ask -A yes=Yes ink
  until_ok 2000 shows ink
  ink=$(island | jq -c .note.actionInk)
  check "$t: the card's chip key and word differ from their fill ($ink)" apart "$ink"
  open_centre
  ink=$(notifs | jq -c .actionInk)
  check "$t: the row's chip key and word differ from their fill ($ink)" apart "$ink"
  close_centre
  done_asking
done

exit $((fails > 0))
}
