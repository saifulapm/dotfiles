#!/usr/bin/env bash
# Mod+/ grows the island into the six-column cheat sheet over the margins; Esc or a click outside closes it, another surface's key turns it into that surface, and a live state that arrives takes the island from it.
{
source "$(dirname "$0")/lib.sh"
source "$(dirname "$0")/pointer.bash"

island() { timeout 0.5 qs ipc call island state 2>/dev/null; }
island_is() { island | jq -e "$@" >/dev/null 2>&1; }
sheet() { timeout 0.5 qs ipc call cheatsheet state 2>/dev/null; }
sheet_is() { sheet | jq -e "$@" >/dev/null 2>&1; }
margins() { timeout 0.5 qs ipc call margins state 2>/dev/null; }
px() { grim -g "$1,$2 1x1" -t ppm - 2>/dev/null | tail -c3 | od -An -tx1 | tr -d ' \n'; }
open_sheet() {
  niri msg action spawn -- dots-call cheatsheet toggle
  until_ok 3000 island_is '.surface == "cheatsheet" and .animating == false'
}
at_rest() { island_is '.surface == null and .width == 176 and .animating == false'; }

until_ok 5000 shell_status >/dev/null
until_ok 3000 at_rest
corner_before=$(px 10 $((oh - 10)))
want=$((ow - 48 < 1160 ? ow - 48 : 1160))

open_sheet
check "Mod+/ opens the cheat sheet in the island, $want px wide ($(island | jq -c '{surface, width}'))" island_is --argjson w "$want" '.surface == "cheatsheet" and .width == $w'
check "its groups are SURFACES, IN SURFACES, WORK, WINDOWS, SYSTEM and TOUCHPAD ($(sheet | jq -c .groups))" sheet_is '.groups == ["SURFACES", "IN SURFACES", "WORK", "WINDOWS", "SYSTEM", "TOUCHPAD"]'
check "and it draws six columns ($(sheet | jq -c '[.columns[].name]'))" sheet_is '[.columns[].name] == .groups'
in_surfaces() { sheet_is '(.columns[] | select(.name == "IN SURFACES") | .rows) as $r | ($r | any(.key == "Esc")) and (["launcher", "control", "notifications", "pass", "tailscale", "accounts", "dns", "goals"] - [$r[].surface] | length == 0)'; }
check "IN SURFACES holds Esc and rows for the launcher, Control, Notifications, Pass, Tailscale, Accounts, DNS and Goals" in_surfaces
named() { sheet_is '[.columns[] | select(.name == "IN SURFACES") | .rows[] | .caption // empty] == ["Every Surface", "Launcher", "Control", "Notifications", "Pass", "Tailscale", "Accounts", "DNS", "Goals"]'; }
check "and names each surface in a caption over its keys ($(sheet | jq -c '[.columns[] | select(.name == "IN SURFACES") | .rows[] | .caption // empty]'))" named
check "the sheet draws nothing under its columns, no legend ($(sheet | jq -c .belowColumns))" sheet_is '.belowColumns == 0'
check "its heading reads Keys ($(sheet | jq -c .heading))" sheet_is '.heading == "Keys"'
check "no veil is drawn: the pixel 10 px in from the bottom left corner is as it was ($(px 10 $((oh - 10))), was $corner_before)" test "$(px 10 $((oh - 10)))" = "$corner_before"

read -r sx sy < <(timeout 0.5 qs ipc call island box island | jq -r '"\((.x + 40) | floor) \((.y + .h - 20) | floor)"')
point click "$sx" "$sy"
sleep 0.3
check "a click on the sheet keeps it open" island_is '.surface == "cheatsheet"'
point click 40 $((oh - 40))
until_ok 2000 at_rest
check "a click on the paper closes it, as Esc does" at_rest

open_sheet
t0=$(now_ms)
wtype -k Escape
until_ok 1000 at_rest
took=$(($(now_ms) - t0))
check "Esc sets surface to null and the width to 176 within 400 ms (${took} ms)" test "$took" -le 400
gap=$(margins | jq -r '.drawn | (.islandLeft - .lineEnd) | floor')
check "and the margins draw again, short of the resting island ($gap, shown $(margins | jq .shown))" eval '[ "$gap" = 20 ] && margins | jq -e .shown >/dev/null'

open_sheet
launcher_is() { timeout 0.5 qs ipc call launcher state 2>/dev/null | jq -e "$@" >/dev/null 2>&1; }
t0=$(now_ms)
niri msg action spawn -- dots-call launcher toggle
until_ok 1000 eval 'island_is ".surface == \"launcher\"" && launcher_is ".open"'
took=$(($(now_ms) - t0))
check "Mod+Space turns the sheet into the launcher within 500 ms (${took} ms)" test "$took" -le 500
timeout 0.5 qs ipc call launcher close
until_ok 2000 at_rest

open_sheet
notify-send hi
until_ok 2000 island_is '.waiting == 1'
check "a notification that arrives waits behind the sheet ($(island | jq -c '{surface, mode, waiting}'))" island_is '.surface == "cheatsheet" and .waiting == 1'
wtype -k Escape
until_ok 3000 island_is '.surface == null and .mode == "notification"'
check "and shows hi once the sheet closes" island_is '.surface == null and (.text | test("hi"))'
timeout 0.5 qs ipc call notifs clear
until_ok 8000 at_rest

open_sheet
{ printf '%s\n' '{"kind":"confirm","device":"Keys","address":"AA:BB:CC:DD:EE:FF","code":"123456","service":""}'; sleep 6; } 9>&- | socat - "UNIX-CONNECT:$XDG_RUNTIME_DIR/dots-bt-$WAYLAND_DISPLAY.sock" >/dev/null 2>&1 9>&- &
pair=$!
until_ok 2000 island_is '.surface == null and .mode == "question"'
check "a pairing request takes the island from the sheet with its card ($(island | jq -c '{surface, mode}'))" island_is '.surface == null and .mode == "question" and .pairing != null'
kill "$pair" 2>/dev/null
exit "$fails"
}
