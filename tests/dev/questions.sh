#!/usr/bin/env bash
# An agent question in the island, answered by Mod+I and a key through a fake mem that records its argv.
{
fake=$(mktemp -d)
calls=$fake/calls
cat >"$fake/mem" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$calls"
EOF
chmod +x "$fake/mem"
PATH=$fake:$PATH
source "$(dirname "$0")/lib.sh"
cleanup() { rm -rf "$fake"; }

until_ok 5000 shell_status >/dev/null
island() { timeout 0.5 qs ipc call island state 2>/dev/null; }
mode_is() { island | jq -e --arg m "$1" '.mode == $m' >/dev/null 2>&1; }
island_focus() { niri msg -j layers | jq -e --arg k "$1" 'any(.[]; .namespace == "dots-island" and .keyboard_interactivity == $k)' >/dev/null; }
mod_i() { niri msg action spawn -- qs ipc call island focus; }
# The hub writes the file whole, through a temp file and a rename.
ask() {
  jq -n --arg id "$1" --arg text "$2" '{self: "macbook", questions: [{id: $id, project: "dotfiles", machine: "mini.ts.net", text: $text, options: ["Import now", "Later"], person: true, popup: true}]}' >"$DOTS_HUB_QUESTIONS.tmp"
  mv "$DOTS_HUB_QUESTIONS.tmp" "$DOTS_HUB_QUESTIONS"
}
answered() { grep -qxF "$1" "$calls" 2>/dev/null; }

written=$(now_ms)
ask Q1 "Import the feed?"
until_ok 2000 mode_is question
state=$(island)
echo "     island: $state"
shows_both() { jq -e '.text | test("Import now") and test("Later")' <<<"$state" >/dev/null; }
check "the question shows both options" shows_both
seen=$(($(jq .since <<<"$state") - written))
check "it shows ${seen} ms after the write, within 200 ms" test "$seen" -le 200
narrow() { jq -e '.width <= 560' <<<"$state" >/dev/null; }
check "the question keeps the island within 560 px" narrow

notify-send hi
sleep 0.3
check "a notification does not take the island from the question" mode_is question
check "the notification still reaches the history" eval 'timeout 0.5 qs ipc call notifs state | jq -e ".summaries[0] == \"hi\"" >/dev/null'

mod_i
until_ok 2000 island_focus Exclusive
check "Mod+I gives the island the keyboard" island_focus Exclusive
wtype -k 1
until_ok 2000 answered "answer --by island -- Q1 Import now"
check "1 calls mem answer with Import now" answered "answer --by island -- Q1 Import now"
# The hi above still has part of its 5 s, so the island may show it next; the question is what must go.
not_question() { ! mode_is question; }
until_ok 1000 not_question
check "the question leaves the island" not_question
check "and gives the keyboard back" island_focus None

ask Q2 "Ship it?"
until_ok 2000 mode_is question
mod_i
until_ok 2000 island_focus Exclusive
wtype -k r
sleep 0.2
wtype 'next week'
wtype -k Return
until_ok 2000 answered "answer --by island -- Q2 next week"
check "r, a typed reply and Enter answer with the reply" answered "answer --by island -- Q2 next week"

ask Q3 "Later?"
until_ok 2000 mode_is question
mod_i
until_ok 2000 island_focus Exclusive
wtype -k Escape
until_ok 1000 not_question
echo "     after Esc: $(island)"
check "Esc puts the question away" not_question
check "Esc answers nothing" eval '! grep -q Q3 "$calls"'
check "Esc gives the keyboard back" island_focus None

until_ok 6000 mode_is rest
check "with the questions answered or put away and the hi gone, the island rests" mode_is rest
mod_i
until_ok 2000 mode_is calendar
state=$(island)
echo "     calendar: $(jq -c '.calendar | {title, today}' <<<"$state")"
this_month() { jq -e --arg t "$(date '+%B %Y')" --argjson d "$(date +%-d)" '.calendar.title == $t and .calendar.today == $d and .width <= 560' <<<"$state" >/dev/null; }
check "Mod+I at rest shows this month's calendar with today marked" this_month
check "the calendar has the keyboard" island_focus Exclusive
wtype -k l
next_month() { island | jq -e --arg t "$(date -d "$(date +%Y-%m-01) +1 month" '+%B %Y')" '.calendar.title == $t' >/dev/null; }
until_ok 1000 next_month
check "l shows the next month" next_month
wtype -k Escape
until_ok 1000 mode_is rest
check "Esc closes the calendar" mode_is rest
check "and gives the keyboard back" island_focus None

# A long header and option must stay inside the card: the strip just right of it, past its 3 px hard shadow, reads as it did before.
strip_rgb() {
  local geo
  geo=$(niri msg -j outputs | jq -r 'first(.[]).logical | "\(.x + (.width / 2 | floor) + 290),\(.y + 10) 30x150"')
  grim -s 1 -t ppm -g "$geo" - | mean_rgb
}
before=$(strip_rgb)
long=$(printf 'x%.0s' $(seq 1 300))
jq -n --arg l "$long" '{self: "macbook", questions: [{id: "Q9", project: $l, machine: $l, text: "Long?", options: [$l, "Later"], popup: true}]}' >"$DOTS_HUB_QUESTIONS.tmp"
mv "$DOTS_HUB_QUESTIONS.tmp" "$DOTS_HUB_QUESTIONS"
until_ok 2000 mode_is question
sleep 0.3
after=$(strip_rgb)
echo "     right of the card: $before before, $after with the question"
check "a 300-character header and option stay inside the 560 px card" test "$after" = "$before"

exit $((fails > 0))
}
