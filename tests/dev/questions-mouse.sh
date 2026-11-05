#!/usr/bin/env bash
# An island question by mouse: a click on the closed card opens it as Mod+I does, a click on an option answers with it, and a click on Reply opens the reply line, behind which no option answers; an option's bidi controls never reorder what the card draws.
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
source "$(dirname "$0")/pointer.bash"
cleanup() {
  pointer_stop
  rm -rf "$fake"
}

island() { timeout 0.5 qs ipc call island state 2>/dev/null; }
mode_is() { island | jq -e --arg m "$1" '.mode == $m' >/dev/null 2>&1; }
ask_is() { island | jq -e ".ask | $1" >/dev/null 2>&1; }
island_focus() { niri msg -j layers | jq -e --arg k "$1" 'any(.[]; .namespace == "dots-island" and .keyboard_interactivity == $k)' >/dev/null; }
# ask <id> <text> <option>...
ask() {
  local id=$1 text=$2
  shift 2
  jq -n --arg id "$id" --arg text "$text" '{self: "macbook", questions: [{id: $id, project: "tambour", machine: "nuc.ts.net", text: $text, options: $ARGS.positional, recommend: null, person: true, popup: true}]}' --args "$@" >"$DOTS_HUB_QUESTIONS.tmp"
  mv "$DOTS_HUB_QUESTIONS.tmp" "$DOTS_HUB_QUESTIONS"
}
called() { grep -qxF -- "$1" "$calls" 2>/dev/null; }
calls_count() { [ -f "$calls" ] && wc -l <"$calls" || echo 0; }
settled() { timeout 0.5 qs ipc call island state 2>/dev/null | jq -e '.animating == false' >/dev/null; }
island_spot() {
  local box
  box=$(timeout 0.5 qs ipc call island box "$1" 2>/dev/null)
  [ -n "$box" ] && [ "$box" != null ] || return 1
  jq -r '"\((.x + .w / 2) | floor) \((.y + .h / 2) | floor)"' <<<"$box"
}
island_drawn() { island_spot "$1" >/dev/null; }
click_island() {
  local at
  # A box still morphing from the last mode has its middle where the next one is not drawn.
  until_ok 2000 settled
  at=$(island_spot "$1") || { echo "no island click area named $1 is drawn"; return 1; }
  # shellcheck disable=SC2086
  point click $at
}

until_ok 5000 shell_status >/dev/null
ask Q2 "Which shot leads the page?" "the resting shot" "the louvres shot"
until_ok 2000 mode_is question
check "closed, the card draws no option to click" bash -c "! timeout 0.5 qs ipc call island box ask:option:1 | grep -q '\"x\"'"
click_island island
until_ok 2000 island_focus Exclusive
until_ok 1000 ask_is '.expanded'
check "a click on the closed card opens it whole, with the keyboard ($(island | jq -c '{focused, expanded: .ask.expanded}'))" ask_is '.expanded'
until_ok 2000 island_drawn ask:option:1
click_island ask:option:1
until_ok 2000 called "answer --by popup -- Q2 the louvres shot"
check "a click on the second option answers with it ($(cat "$calls" 2>/dev/null))" called "answer --by popup -- Q2 the louvres shot"

# The hub takes the answered question away; a new one comes.
: >"$calls"
ask Q3 "Ship it tonight?" "yes" "no"
until_ok 2000 mode_is question
click_island island
until_ok 2000 island_drawn ask:option:2
at=$(island_spot ask:option:0)
click_island ask:option:2
until_ok 2000 ask_is '.replying'
check "a click on Reply opens the reply line ($(island | jq -c '.ask.replying'))" ask_is '.replying'
# shellcheck disable=SC2086
point click $at
# A click has nothing to wait for, so the check gives the shell its moment.
until_ok 1000 test -s "$calls"
check "behind the reply line, a click where the first option was answers nothing ($(calls_count) calls)" test "$(calls_count)" -eq 0
check "and the reply line keeps the keyboard ($(island | jq -c '.ask.replying'))" ask_is '.replying'

# An option's bidi controls are the asker's: the card draws its words in order, and a click answers with the option as asked.
wtype -k Escape
: >"$calls"
forged=$(printf 'live \u202Eliat gnirts')
ask Q4 "Which?" "$forged" "plain"
# The project is the asker's too.
jq --arg p "$(printf '\u202Eprojekt')" '.questions[0].project = $p' "$DOTS_HUB_QUESTIONS" >"$DOTS_HUB_QUESTIONS.tmp"
mv "$DOTS_HUB_QUESTIONS.tmp" "$DOTS_HUB_QUESTIONS"
until_ok 2000 mode_is question
click_island island
until_ok 2000 island_drawn ask:option:0
until_ok 2000 ask_is '.where == "projekt · nuc"'
check "the header draws the project without its bidi control ($(island | jq -c '.ask.where'))" ask_is '.where == "projekt · nuc"'
check "the option draws without its bidi control ($(island | jq -c '.ask.options[0].text'))" ask_is '.options[0].text == "1 · live liat gnirts"'
click_island ask:option:0
until_ok 2000 called "answer --by popup -- Q4 $forged"
check "and a click answers with the option as asked" called "answer --by popup -- Q4 $forged"

exit $((fails > 0))
}
