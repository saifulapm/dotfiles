#!/usr/bin/env bash
# An agent question's card: two lines and a summary until Mod+I opens it whole, its options in full with the recommended one starred, its web addresses links, a refused answer said on the card, and files from the picker, the clipboard or a drop going with the answer.
{
fake=$(mktemp -d)
calls=$fake/calls opened=$fake/opened
# mem refuses an answer to QF as the hub refuses one it cannot pass on.
cat >"$fake/mem" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$calls"
case "\$*" in *" QF "*) echo "mem: #QF was asked on nuc; only a slack, popup or cli answer travels between machines" >&2; exit 1 ;; esac
EOF
cat >"$fake/xdg-open" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$opened"
EOF
chmod +x "$fake/mem" "$fake/xdg-open"
PATH=$fake:$PATH
source "$(dirname "$0")/lib.sh"
cleanup() { rm -rf "$fake"; }
dots_pointer_build || echo "     dots-pointer did not build"

until_ok 5000 shell_status >/dev/null
island() { timeout 0.5 qs ipc call island state 2>/dev/null; }
mode_is() { island | jq -e --arg m "$1" '.mode == $m' >/dev/null 2>&1; }
ask_is() { local a=("$@"); island | jq -e "${a[@]:0:$#-1}" ".ask | ${a[-1]}" >/dev/null 2>&1; }
island_focus() { niri msg -j layers | jq -e --arg k "$1" 'any(.[]; .namespace == "dots-island" and .keyboard_interactivity == $k)' >/dev/null; }
mod_i() { niri msg action spawn -- dots-call island focus; }
pk_state() { timeout 0.5 dots-call picker state 2>/dev/null; }
# ask <id> <text> [recommend] [option...]
ask() {
  local id=$1 text=$2 rec=$3
  shift 3
  jq -n --arg id "$id" --arg text "$text" --arg rec "$rec" '{self: "macbook", questions: [{id: $id, project: "tambour", machine: "nuc.ts.net", text: $text, options: $ARGS.positional, recommend: (if $rec == "" then null else $rec end), person: true, popup: true}]}' --args "$@" >"$DOTS_HUB_QUESTIONS.tmp"
  mv "$DOTS_HUB_QUESTIONS.tmp" "$DOTS_HUB_QUESTIONS"
}
called() { grep -qxF -- "$1" "$calls" 2>/dev/null; }

long="https://example.com/listing leads the card. $(printf 'Both shots are in the release folder and nothing waits on this choice. %.0s' $(seq 1 6))"
rest="the resting shot, which shows the film and then New in on its rail below it, as the home page does on a first visit"
ask Q1 "$long" "$rest" "the louvres shot" "$rest" "neither"
until_ok 2000 mode_is question
state=$(island)
echo "     closed: $(jq -c '.ask | {expanded, lines, truncated, summary, links}' <<<"$state")"
check "closed, the card shows two lines of the question, cut short" ask_is '.expanded == false and .lines == 2 and .truncated'
check "and a summary with the recommended option" ask_is --arg s "3 options · ★ $rest" '.summary == $s and .options == []'
check "the web address is a link" ask_is '.links == ["https://example.com/listing"]'

mod_i
until_ok 2000 island_focus Exclusive
until_ok 1000 ask_is '.expanded'
state=$(island)
echo "     open: $(jq -c '.ask | {lines, truncated, summary, options}' <<<"$state")"
check "Mod+I opens the whole question" ask_is '.expanded and .truncated == false and .lines > 2 and .summary == null'
check "every option shows in full, wrapped, and Reply last" ask_is '[.options[].elided] == [false, false, false, false] and .options[1].lines > 1 and (.options[3].text | startswith("r · Reply"))'
check "the recommended option is starred, not the first" ask_is '[.options[].recommended] == [false, true, false, false] and (.options[1].text | endswith("★"))'

# A click on the link's first letters, which start the text.
read -r tx ty win < <(jq -r '.ask | "\(.textAt[0]) \(.textAt[1]) \(.window)"' <<<"$state")
box=$(niri msg -j outputs | jq -r 'first(.[]).logical | "\(.x),\(.y),\(.width),\(.height)"')
IFS=, read -r ox oy ow _ <<<"$box"
dots-pointer "$box" move $((ox + (ow - win) / 2 + tx + 20)) $((oy + ty + 10)) wait 100 click left >/dev/null 2>&1
check "a click on the link opens it" until_ok 2000 grep -qxF "https://example.com/listing" "$opened"

wtype -M ctrl -k v -m ctrl
check "ctrl+V with no image on the clipboard says so" until_ok 2000 ask_is '.note == "No image on the clipboard" and .attached == []'
grim -g "0,0 8x8" "$fake/shot.png" && wl-copy -t image/png <"$fake/shot.png"
wtype -M ctrl -k v -m ctrl
check "ctrl+V attaches the clipboard's image" until_ok 2000 ask_is '(.attached | length) == 1 and (.attached[0] | test("^Q1-[0-9]+\\.png$")) and .note == ""'

mkdir -p "$fake/files"
echo report >"$fake/files/report.txt"
wtype -k a
until_ok 4000 eval 'pk_state | jq -e ".open and .settled and .listed" >/dev/null'
check "a opens the file picker, which takes the keyboard" island_focus None
wtype -M ctrl l -m ctrl
until_ok 2000 eval 'pk_state | jq -e .pathMode >/dev/null'
wtype "$fake/files/" -k Return
until_ok 3000 eval 'pk_state | jq -e --arg f "$fake/files" ".folder == \$f and .listed" >/dev/null'
wtype -k Return
until_ok 3000 eval 'pk_state | jq -e ".open == false" >/dev/null'
check "a file chosen in the picker is attached ($(island | jq -c .ask.attached))" until_ok 2000 ask_is '.attached[1] == "report.txt"'
check "and the island has the keyboard back" until_ok 2000 island_focus Exclusive

want="answer --by popup --screenshot $XDG_RUNTIME_DIR/dots-island-attach/$(island | jq -r '.ask.attached[0]') --screenshot $fake/files/report.txt -- Q1 $rest"
wtype -k 2
check "2 answers with both attachments" until_ok 2000 called "$want"
tail -1 "$calls" | sed 's/^/     mem /'

ask QF "Refused?" "" "go" "hold"
until_ok 2000 mode_is question
mod_i
until_ok 2000 island_focus Exclusive
wtype -k 1
until_ok 2000 called "answer --by popup -- QF go"
check "a refused answer keeps the question and says why on the card" until_ok 2000 ask_is '.failed | startswith("#QF was asked on nuc")'
sleep 1
check "and asks mem once, not again and again" test "$(grep -c ' QF ' "$calls")" = 1

very=$(printf 'A long line of the question that goes on. %.0s' $(seq 1 120))
ask Q2 "$very" "" "yes" "no"
until_ok 2000 mode_is question
mod_i
until_ok 1000 ask_is '.expanded'
screen_h=$(niri msg -j outputs | jq -r 'first(.[]).logical.height')
check "a question taller than the screen scrolls in a card of 80% of its height" eval 'island | jq -e --argjson h "$screen_h" ".ask.scrolls and .height <= (\$h * 0.8 | round)" >/dev/null'
wtype -k Escape

exit $((fails > 0))
}
