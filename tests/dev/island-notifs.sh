#!/usr/bin/env bash
# Mod+A grows the island into the notification centre as board 5 draws it: 640 px wide, the header's count, each app under its head newest first, Clear all to "Nothing new", and no legend.
{
source "$(dirname "$0")/lib.sh"

island() { timeout 0.5 qs ipc call island state 2>/dev/null; }
island_is() { island | jq -e "$@" >/dev/null 2>&1; }
notifs() { timeout 0.5 qs ipc call notifs state 2>/dev/null; }
notifs_is() { notifs | jq -e "$@" >/dev/null 2>&1; }
at_rest() { island_is '.surface == null and .animating == false'; }
surfaces_focus() { niri msg -j layers | jq -e --arg k "$1" 'any(.[]; .namespace == "dots-surfaces" and .keyboard_interactivity == $k)' >/dev/null; }
# niri runs no binds for wtype's virtual keyboard, so the check spawns the bind's command through niri.
mod_a() { niri msg action spawn -- dots-call notifs toggle; }
open_centre() {
  mod_a
  until_ok 3000 island_is '.surface == "notifs" and .animating == false'
  until_ok 2000 surfaces_focus Exclusive
  until_ok 2000 notifs_is '.keyboard and .settled'
}

until_ok 5000 shell_status >/dev/null
until_ok 5000 at_rest
read -r ow _ < <(niri msg -j outputs | jq -r '.[] | .logical | "\(.width) \(.height)"')
want=$((ow - 48 < 640 ? ow - 48 : 640))

open_centre
check "Mod+A sets surface to notifs and the island $want px wide ($(island | jq -c '{surface, width}'))" island_is --argjson w "$want" '.surface == "notifs" and .width == $w'
check "with none, the centre draws Nothing new ($(notifs | jq -c '{empty, emptyText}'))" notifs_is '.empty and .emptyText == "Nothing new"'
# No legend: the island is the header, the 120 px empty state and the padding, and nothing more.
check "the centre draws no legend row: the island is 16 + 40 + 8 + 120 + 16 px tall ($(island | jq -c '{height}'))" island_is '.height == 200'
wtype -k Escape
until_ok 3000 at_rest

notify-send -a Mail "One" "the first body"
until_ok 2000 notifs_is '.count == 1'
notify-send -a Mail "Two" "the second body"
until_ok 2000 notifs_is '.count == 2'
until_ok 8000 island_is '.mode == "rest"'
open_centre
echo "     notifs: $(notifs | jq -c '{groups, countText, heads, rows}')"
check "one Mail group lists Two above One" notifs_is '.groups == [{app: "Mail", entries: ["Two", "One"]}]'
check "the header reads Notifications and counts 2" notifs_is '.heading == "Notifications" and .countText == "2"'
check "the Mail head draws a 22 px circle with M and no badge" notifs_is '[.heads[] | {app, letter, circle, badge, selected}] == [{app: "Mail", letter: "M", circle: 22, badge: "", selected: false}]'
check "it opens on Two, the newest, which alone is lighter" notifs_is '.selectedKind == "note" and ([.notes[] | select(.selected) | .summary] == ["Two"]) and (.notes[0].fill != .notes[1].fill)'
check "each tile draws its body on one line and an age ($(notifs | jq -c '[.notes[] | {body, age}]'))" notifs_is '[.notes[] | .body] == ["the second body", "the first body"] and all(.notes[]; .age == "now")'
check "the DND switch is off" notifs_is '.dndOn == false'
fits() { local h c; h=$(island | jq .height); c=$(notifs | jq .contentHeight); awk -v h="$h" -v c="$c" 'BEGIN { exit !(h - (64 + c + 16) < 1 && (64 + c + 16) - h < 1) }'; }
check "the island is the header, the rows and the padding, no legend ($(island | jq .height) px for $(notifs | jq .contentHeight) px of rows)" fits

# A notification arriving while the centre is open joins the top of its group at once, and nothing waits for the close.
notify-send -a Mail "Three"
until_ok 1000 notifs_is '.groups[0].entries[0] == "Three"'
check "Three joins the top of the Mail group at once ($(notifs | jq -c .groups))" notifs_is '.groups == [{app: "Mail", entries: ["Three", "Two", "One"]}] and .countText == "3"'
check "and the island's waiting stays 0 ($(island | jq -c '{waiting}'))" island_is '.waiting == 0'
wtype -k Escape
until_ok 3000 at_rest
sleep 0.5
check "after the close Three does not show on the island ($(island | jq -c '{mode}'))" island_is '.mode == "rest"'
open_centre

# Shift+D clears all, as the header's Clear all does.
wtype -M shift -k d -m shift
until_ok 2000 notifs_is '.count == 0'
check "Clear all empties the list and draws Nothing new" notifs_is '.count == 0 and .empty and .emptyText == "Nothing new"'
wtype -k Escape
until_ok 3000 at_rest
check "Esc closes the centre and gives the keyboard back" surfaces_focus None

# Mod+Shift+A clears and Mod+D toggles Do Not Disturb without opening anything; the check spawns each bind's command through niri.
notify-send -t 1 -a Mail "Four"
until_ok 2000 notifs_is '.count == 1'
until_ok 3000 island_is '.mode == "rest"'
niri msg action spawn -- dots-call notifs clear
until_ok 2000 notifs_is '.count == 0'
sleep 0.3
check "Mod+Shift+A clears the list and the island's surface stays null ($(island | jq -c '{surface}'))" island_is '.surface == null'
niri msg action spawn -- dots-call notifs toggleDnd
until_ok 2000 notifs_is '.dnd == true'
sleep 0.3
check "Mod+D turns Do Not Disturb on and the surface stays null ($(island | jq -c '{surface}'))" island_is '.surface == null'
niri msg action spawn -- dots-call notifs toggleDnd
until_ok 2000 notifs_is '.dnd == false'
check "and Mod+D again turns it off, still with no surface" island_is '.surface == null'
exit "$fails"
}
