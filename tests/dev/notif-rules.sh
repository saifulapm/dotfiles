#!/usr/bin/env bash
# Per-app rules from Mod+A on the selected row's app, by its exact name: m mutes it, i lets it through Do Not Disturb.
{
source "$(dirname "$0")/lib.sh"

until_ok 5000 shell_status >/dev/null
notifs() { timeout 0.5 qs ipc call notifs state 2>/dev/null; }
state_is() { notifs | jq -e "$@" >/dev/null; }
island() { timeout 0.5 qs ipc call island state 2>/dev/null; }
mode_is() { island | jq -e --arg m "$1" '.mode == $m' >/dev/null 2>&1; }
shows() { island | jq -e --arg s "$1" '.mode == "notification" and (.text | contains($s))' >/dev/null 2>&1; }
listed() { state_is --arg s "$1" 'any(.summaries[]; . == $s)'; }
# The caps voices write the app name in capitals and the rule as it is.
had_head() { jq -e --arg t "$1" 'any(.heads[]; .text | ascii_downcase == $t)' <<<"$seen" >/dev/null; }
# niri runs no binds for wtype's virtual keyboard, so the check spawns the bind's command through niri.
focus_is() { niri msg -j layers | jq -e --arg k "$1" 'any(.[]; .namespace == "dots-surfaces" and .layer == "Overlay" and .keyboard_interactivity == $k)' >/dev/null; }
centre_open() { state_is .open && focus_is Exclusive; }
centre_closed() { state_is '.open == false' && focus_is None; }
# Opening the centre selects its first row, the newest app's, and the key acts on that app; seen keeps the centre as it then drew.
seen=
key_on_newest() {
  niri msg action spawn -- dots-call notifs open
  until_ok 3000 centre_open
  wtype "${@:-}"
  sleep 0.3
  seen=$(notifs)
  wtype -k Escape
  until_ok 2000 centre_closed
}
# The shell adds an entry to the history before it shows it, so once it is listed the island has already taken it or not.
sent_rests() {
  until_ok 2000 listed "$1"
  sleep 0.5
  mode_is rest
}

notify-send -t 1 -a T first
until_ok 2000 listed first
until_ok 2000 mode_is rest
key_on_newest -k m
check "m on a T row: the heading ends · muted ($(jq -c '[.heads[].text]' <<<"$seen"))" had_head "t · 1 · muted"

notify-send -a T x
check "a muted T's notification keeps the island at rest" sent_rests x
check "Mod+A lists it" listed x
notify-send -u critical -a T y
check "a muted T's critical keeps the island at rest, and Mod+A lists it" sent_rests y

notify-send -t 1 -a slack s1
until_ok 2000 listed s1
until_ok 2000 mode_is rest
notify-send -t 1 -a Slack s2
until_ok 2000 listed s2
until_ok 2000 mode_is rest
notify-send -t 1 -a slack s3
until_ok 2000 listed s3
until_ok 2000 mode_is rest
key_on_newest -k m
check "muting slack leaves Slack with no rule ($(notifs | jq -c .rules))" state_is '.rules.slack.muted and (.rules | has("Slack") | not)'
notify-send -a Slack s4
check "a Slack notification still shows" until_ok 2000 shows s4
until_ok 7000 mode_is rest
# wtype -k D sends the keysym without Shift, which Qt reads as d, so the check holds Shift as a person does.
key_on_newest -M shift -k d -m shift
check "D clears the history" state_is '.count == 0'
notify-send -a T w
check "after D clears the history, a muted T still keeps the island at rest" sent_rests w
key_on_newest -k m
check "m again: the heading has no suffix ($(jq -c '[.heads[].text]' <<<"$seen"))" had_head "t · 1"
notify-send -a T v
check "and the next T notification shows" until_ok 2000 shows v
until_ok 7000 mode_is rest

timeout 0.5 qs ipc call notifs dnd true >/dev/null
key_on_newest -k i
check "i under Do Not Disturb: the heading ends · through DND ($(jq -c '[.heads[].text]' <<<"$seen"))" had_head "t · 2 · through dnd"
notify-send -a U u1
check "a U notification under Do Not Disturb keeps the island at rest" sent_rests u1
notify-send -a T d1
check "a T one shows" until_ok 2000 shows d1
timeout 0.5 qs ipc call notifs dnd false >/dev/null

exit $((fails > 0))
}
