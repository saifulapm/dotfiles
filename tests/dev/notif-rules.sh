#!/usr/bin/env bash
# Per-app rules from Mod+A on the selected row's app, by its exact name: m mutes it, i lets it through Do Not Disturb, s sets how long it stays; notifications.json keeps them.
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
  [ $# -eq 0 ] || wtype "$@"
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
until_ok 7000 mode_is rest

heads=()
for _ in 1 2 3 4; do
  key_on_newest -k s
  heads+=("$(jq -r '.heads[0].text' <<<"$seen")")
done
check "s four times: 3 s, 10 s, until dismissed, then no stay ($(printf '%s; ' "${heads[@]}"))" \
  test "${heads[*],,}" = "t · 3 · through dnd · stays 3 s t · 3 · through dnd · stays 10 s t · 3 · through dnd · stays until dismissed t · 3 · through dnd"
key_on_newest -k s -k s -k m
check "all three on one app ($(jq -c '[.heads[].text]' <<<"$seen"))" had_head "t · 3 · muted · through dnd · stays 10 s"
key_on_newest -k m

# Each held time runs from the state read as it showed to the shell's mode change back to rest.
held_since() { echo $(($(island | jq .since) - $1)); }
notify-send -t 2000 -a T z
until_ok 2000 shows z
since=$(island | jq .since)
until_ok 12000 mode_is rest
held=$(held_since "$since")
check "with stays 10 s, -t 2000 holds 10 s (${held} ms)" test "$held" -ge 9900 -a "$held" -le 10500

key_on_newest -k s
notify-send -a T z2
until_ok 2000 shows z2
sleep 15
check "with stays until dismissed, it is still shown after 15 s" shows z2
key_on_newest -k d
check "d in Mod+A dismisses it" until_ok 2000 mode_is rest

key_on_newest -k s -k s
check "s twice more: stays 3 s ($(jq -c '[.heads[].text]' <<<"$seen"))" had_head "t · 4 · through dnd · stays 3 s"
notify-send -t 0 -a T w2
until_ok 2000 shows w2
since=$(island | jq .since)
until_ok 5000 mode_is rest
held=$(held_since "$since")
check "with stays 3 s, -t 0 leaves after 3 s (${held} ms)" test "$held" -ge 2900 -a "$held" -le 3500

# A long app name elides before its rule, so the heading still ends with it.
long=$(printf 'long%.0s' {1..40})
notify-send -t 1 -a "$long" l1
until_ok 2000 listed l1
until_ok 2000 mode_is rest
key_on_newest -k m
long_head() { jq -e '. as $s | any(.heads[]; (.text | ascii_downcase | startswith("long")) and .elided and .rule == " · muted" and .ruleRight <= $s.cardRight)' <<<"$seen" >/dev/null; }
check "a long app name elides and its · muted is drawn whole ($(jq -c '[.heads[] | {text: .text[-12:], elided, rule, ruleRight}] + [{cardRight}]' <<<"$seen"))" long_head

# Criticals set aside come back newest first; a muted app's is passed over, not left blocking the older one.
notify-send -u critical -a D d2
until_ok 2000 shows d2
notify-send -u critical -a C c1
until_ok 2000 shows c1
notify-send -a N n1
until_ok 2000 shows n1
key_on_newest -k j -k m
check "j, m on the C row mutes C ($(notifs | jq -c .rules.C))" state_is '.rules.C.muted'
check "as N leaves, D's critical comes back past the muted C's" until_ok 7000 shows d2

store=$XDG_STATE_HOME/dots/notifications.json
store_is() { jq -e "$1" "$store" >/dev/null; }
check "notifications.json holds rules with key T beside dnd ($(jq -c .rules "$store"))" store_is '(.rules.T == {dnd: true, stays: 3000}) and (.rules.slack == {muted: true}) and has("dnd")'
key_on_newest
before=$(jq -c '[.heads[].text]' <<<"$seen")
check "the legend shows m mute, i DND and s stay ($(jq -c .legend <<<"$seen"))" eval 'jq -e ".legend | ascii_downcase | contains(\"m mute  i dnd  s stay\")" <<<"$seen" >/dev/null'
systemctl --user kill -s KILL "$DOTS_DEV_UNIT"
# The unit restarts after 500 ms; until then the old instance's socket may still answer.
sleep 0.8
until_ok 5000 shell_status >/dev/null
key_on_newest
check "after a shell restart the heading suffixes read as before ($before)" test "$(jq -c '[.heads[].text]' <<<"$seen")" = "$before"

# A store saved before v2.6 has no rules.
printf '{"dnd":false,"history":[{"key":"1-1","id":1,"app":"old","summary":"old 1","body":"b","time":1,"actions":[]}]}\n' >"$store"
systemctl --user kill -s KILL "$DOTS_DEV_UNIT"
sleep 0.8
until_ok 5000 shell_status >/dev/null
check "a notifications.json from before v2.6 loads its history unchanged, with no rules ($(notifs | jq -c '[.summaries, .rules]'))" state_is '.summaries == ["old 1"] and .rules == {} and .dnd == false'

exit $((fails > 0))
}
