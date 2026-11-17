#!/usr/bin/env bash
# Board 2's agent question: a 520 px card with a robot in its header and the options as buttons, the first inverted, with no number drawn; Mod+I then Enter answers the first, and a question takes the island from the calendar.
{
fake=$(mktemp -d)
calls=$fake/calls
cat >"$fake/mem" <<EOF
printf '%s\n' "\$*" >>"$calls"
EOF
chmod +x "$fake/mem"
PATH=$fake:$PATH
source "$(dirname "$0")/lib.sh"
cleanup() { rm -rf "$fake"; }

island() { timeout 0.5 qs ipc call island state 2>/dev/null; }
island_is() { island | jq -e "$@" >/dev/null 2>&1; }
settled() { until_ok "${2:-3000}" island_is "$1 and .animating == false"; }
keyboard_is() { niri msg -j layers | jq -e --arg k "$1" 'any(.[]; .namespace == "dots-surfaces" and .keyboard_interactivity == $k)' >/dev/null; }
# Mod+I, then wait until niri has handed the window the keyboard, so the next key reaches the island.
mod_i() { niri msg action spawn -- dots-call island focus; until_ok 2000 keyboard_is Exclusive; }
ask() {
  local id=$1 text=$2
  shift 2
  jq -n --arg id "$id" --arg text "$text" '{self: "macbook", questions: [{id: $id, project: "tambour", machine: "nuc.ts.net", text: $text, options: $ARGS.positional, recommend: null, person: true, popup: true}]}' --args "$@" >"$DOTS_HUB_QUESTIONS.tmp"
  mv "$DOTS_HUB_QUESTIONS.tmp" "$DOTS_HUB_QUESTIONS"
}
called() { grep -qxF -- "$1" "$calls" 2>/dev/null; }

until_ok 5000 island_is '.mode == "rest"'
ask Q1 "Ship the release?" "Ship it" "Wait a day" "Never"
settled '.mode == "question"'
check "a question with three options draws at 520 px ($(island | jq .width))" island_is '.width == 520'
echo "     ask: $(island | jq -c '.ask | {where, clock, expanded}')"
check "its header names who asks and the clock" island_is --arg c "$(date +%H:%M)" '.ask.where == "tambour · nuc" and .ask.clock == $c'
mod_i
settled '.mode == "question" and .focused'
echo "     options: $(island | jq -c '.ask.options')"
check "Mod+I shows the options as buttons with no number: Ship it inverted, the rest quiet, then Reply…" island_is '[.ask.options[] | [.text, .primary]] == [["Ship it", true], ["Wait a day", false], ["Never", false], ["Reply…", false]]'
wtype -k Return
check "Enter answers the first option ($(tail -1 "$calls" 2>/dev/null))" until_ok 2000 called "answer --by popup -- Q1 Ship it"
printf '{"self": "macbook", "questions": []}\n' >"$DOTS_HUB_QUESTIONS"
until_ok 3000 island_is '.mode == "rest"'

# The calendar opens from a click on the resting island; a question arriving takes the island from it, as today.
niri msg action spawn -- dots-call island focus
settled '.mode == "calendar"'
check "the calendar is open" island_is '.mode == "calendar"'
ask Q2 "Now?" "Yes" "No"
check "a question arriving while the calendar is open takes the island" until_ok 3000 island_is '.mode == "question"'
exit "$fails"
}
