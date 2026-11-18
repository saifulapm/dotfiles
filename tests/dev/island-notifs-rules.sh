#!/usr/bin/env bash
# Enter on an app's head in the island's centre opens its rules tile: Mute, Show during Do Not Disturb (greyed while muted) and Stays on screen's pills; a muted app's critical still shows, Stays on screen at 3 s holds its next one 3 to 4 s, and the head's badge reads the rule.
{
source "$(dirname "$0")/lib.sh"

island() { timeout 0.5 qs ipc call island state 2>/dev/null; }
island_is() { island | jq -e "$@" >/dev/null 2>&1; }
notifs() { timeout 0.5 qs ipc call notifs state 2>/dev/null; }
notifs_is() { notifs | jq -e "$@" >/dev/null 2>&1; }
at_rest() { island_is '.surface == null and .animating == false'; }
surfaces_focus() { niri msg -j layers | jq -e --arg k "$1" 'any(.[]; .namespace == "dots-surfaces" and .keyboard_interactivity == $k)' >/dev/null; }
mod_a() { niri msg action spawn -- dots-call notifs toggle; }
open_centre() {
  mod_a
  until_ok 3000 island_is '.surface == "notifs" and .animating == false'
  until_ok 2000 surfaces_focus Exclusive
  until_ok 2000 notifs_is '.keyboard and .settled'
}
close_centre() {
  wtype -k Escape
  until_ok 3000 at_rest
}
key() { wtype -k "$1"; sleep 0.15; }
shows() { island_is --arg s "$1" '.mode == "notification" and (.text | contains($s))'; }
listed() { notifs_is --arg s "$1" 'any(.summaries[]; . == $s)'; }
mail_rule() { notifs | jq -c '.rules.Mail'; }

until_ok 5000 shell_status >/dev/null
until_ok 5000 at_rest
notify-send -t 1 -a Mail "hello"
until_ok 2000 listed hello
until_ok 3000 island_is '.mode == "rest"'

open_centre
# It opens on hello; k is Mail's head, and Enter there opens its rules with Mute selected.
key k
check "k from the first tile selects Mail's head" notifs_is '.selectedKind == "head"'
key Return
until_ok 1000 notifs_is '.openRules == "Mail"'
echo "     rules: $(notifs | jq -c '[.ruleRows[] | {field, label, on, greyed, pills: [.pills[] | [.text, .on]]}]')"
check "Enter on the Mail head opens one tile of Mute, Show during Do Not Disturb and Stays on screen" notifs_is '[.ruleRows[].label] == ["Mute", "Show during Do Not Disturb", "Stays on screen"] and .selectedKind == "rule"'
check "Stays on screen draws Default, 3 s, 10 s and Until dismissed, Default lit" notifs_is '[.ruleRows[2].pills[] | [.text, .on]] == [["Default", true], ["3 s", false], ["10 s", false], ["Until dismissed", false]]'

# Mute on: Show during Do Not Disturb greys and Enter there does nothing.
key Return
until_ok 1000 notifs_is '.rules.Mail.muted == true'
check "Enter on Mute mutes Mail ($(mail_rule)) and its badge reads Muted" notifs_is '.ruleRows[0].on and (.heads[0].badge == "Muted")'
check "with Mute on, Show during Do Not Disturb is greyed" notifs_is '.ruleRows[1].greyed and (.ruleRows[0].greyed | not)'
key j
key Return
sleep 0.3
check "and Enter on it does not toggle it ($(mail_rule))" notifs_is '.rules.Mail.dnd != true'
key i
sleep 0.3
check "nor does i while Mail is muted ($(mail_rule))" notifs_is '.rules.Mail.dnd != true'
# Esc closes the rules tile first, then the centre.
key Escape
close_centre

notify-send -a Mail x
until_ok 2000 listed x
sleep 0.5
check "a muted Mail's notification shows nothing in the island" island_is '.mode == "rest"'
notify-send -a Mail -u critical y
check "a muted Mail's critical still shows" until_ok 2000 shows y
# Mod+A then d on it puts it away; its tile is the newest.
open_centre
wtype -k d
until_ok 2000 notifs_is '[.summaries[] | select(. == "y")] == []'
close_centre

# Mute off again, then Stays on screen at 3 s with l from Default.
open_centre
key k
key Return
until_ok 1000 notifs_is '.openRules == "Mail"'
key Return
until_ok 1000 notifs_is '.rules.Mail.muted != true'
key j
key j
key l
until_ok 1000 notifs_is '.rules.Mail.stays == 3000'
check "l on Stays on screen lights 3 s ($(mail_rule))" notifs_is '[.ruleRows[2].pills[] | select(.on) | .text] == ["3 s"]'
check "and the badge reads 3 s" notifs_is '.heads[0].badge == "3 s"'
# Esc closes the rules tile first, then the centre.
key Escape
check "Esc closes the rules tile and leaves the centre open" notifs_is '.open and .openRules == "" and .selectedKind == "head"'
close_centre

# A notification arriving into a Mail rule of 3 s leaves the island between 3 and 4 s after it showed.
notify-send -a Mail -t 20000 "short"
until_ok 2000 shows short
t0=$(date +%s%3N)
until_ok 6000 island_is '.mode == "rest"'
held=$(($(date +%s%3N) - t0))
check "with Stays on screen at 3 s, a Mail notification leaves after 3 to 4 s (${held} ms)" test "$held" -ge 2900 -a "$held" -le 4000
exit "$fails"
}
