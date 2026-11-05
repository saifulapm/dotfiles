#!/usr/bin/env bash
# The picker answers the mouse as a file manager does: a click selects, Shift and Ctrl mark, a double click does Enter's work, a place opens, the wheel scrolls, and nothing acts behind a question or the path field.
{
source "$(dirname "$0")/lib.sh"
source "$(dirname "$0")/pointer.bash"

sock=$XDG_RUNTIME_DIR/dots-picker-$WAYLAND_DISPLAY.sock
dl=$DOTS_DEV_DIR/mouse/Downloads big=$DOTS_DEV_DIR/mouse/big docs=$DOTS_DEV_DIR/mouse/docs out=$DOTS_DEV_DIR/answers
mkdir -p "$dl/sub" "$big" "$docs" "$out"
: >"$dl/sub/inner.txt"
for i in 1 2 3 4 5 6 7 8; do : >"$dl/f0$i.txt"; done
for i in $(seq 10 69); do : >"$big/g$i.txt"; done
: >"$docs/notes.md"
: >"$docs/report.pdf"

pk_state() { timeout 0.5 dots-call picker state 2>/dev/null; }
state_is() { pk_state | jq -e "$@" >/dev/null 2>&1; }
request() { jq -cn --arg mode "$1" --arg folder "$2" --argjson multiple "${3-false}" --arg name "${4-}" '{mode: $mode, multiple: $multiple, title: "", app: "chromium-browser", folder: $folder, name: $name, filters: [], filter: 0, accept: ""}'; }
ask() {
  rm -f "$out/$1"
  node -e '
    const [sock, line, file] = process.argv.slice(1), chunks = [];
    const s = require("net").connect(sock, () => s.write(line + "\n"));
    s.on("data", (d) => chunks.push(d));
    s.on("close", () => require("fs").writeFileSync(file, Buffer.concat(chunks)));
  ' "$sock" "$2" "$out/$1" &
  pid=$!
}
answered() { [ -e "$out/$1" ]; }
answer_is() { [ "$(cat "$out/$1")" = "$2" ]; }
# Gives the picker 800 ms to answer what it must not.
unanswered() { ! until_ok 800 answered "$1"; }
chosen() { jq -cn '{response: 0, paths: $ARGS.positional}' --args "$@"; }
shown() { until_ok 4000 state_is '.open and .settled and .listed'; }
# The click areas are named by row and place index.
click_at() { local at; at=$(shell_spot "$1") && point click $at; }
dclick_at() { local at; at=$(shell_spot "$1") && point dclick $at "${2-100}"; }
mod_at() { local at; at=$(shell_spot "$2") && mod_click "$1" $at; }
finish() { wtype -k Escape; until_ok 3000 answered "$1"; }
rows_drawn() { until_ok 4000 bash -c "[ -n \"\$(timeout 0.5 qs ipc call shell box picker-row:1)\" ]"; }

# Rows by name sort: sub/ is row 0, f01.txt row 1, and so on.
ask pick "$(request open "$dl")"
shown
rows_drawn
click_at picker-row:3
check "a click on the third file selects only it ($(pk_state | jq -c '[.rows[.selected].name, .selected, .marked]'))" until_ok 2000 state_is '.rows[.selected].name == "f03.txt" and .selected == 3 and .marked == []'
check "and the picker stays open" state_is '.open'
point move 5 5
check "a pointer at rest moves nothing" state_is '.selected == 3'
dclick_at picker-row:5
until_ok 3000 answered pick
check "a double click on a file answers that file ($(cat "$out/pick" 2>/dev/null))" answer_is pick "$(chosen "$dl/f05.txt")"

ask enter "$(request open "$dl")"
shown
rows_drawn
dclick_at picker-row:0
check "a double click on a folder enters it ($(pk_state | jq -c '[.folder, [.rows[].name]]'))" until_ok 3000 state_is --arg f "$dl/sub" '.folder == $f and .listed and [.rows[].name] == ["inner.txt"]'
check "and answers nothing" unanswered enter
finish enter

ask slow "$(request open "$dl")"
shown
rows_drawn
dclick_at picker-row:2 600
check "two clicks 600 ms apart leave the file selected ($(pk_state | jq -c '[.rows[.selected].name, .selected]'))" state_is '.rows[.selected].name == "f02.txt" and .open'
check "and answer nothing" unanswered slow
finish slow

ask several "$(request open "$dl" true)"
shown
rows_drawn
click_at picker-row:1
mod_at shift picker-row:3
check "a click then a Shift-click marks the files from one to the other ($(pk_state | jq -c '[.selected, .marked]'))" until_ok 2000 state_is '.selected == 3 and .marked == ["f01.txt", "f02.txt", "f03.txt"]'
wtype -k Return
until_ok 3000 answered several
check "Enter on a marked file answers exactly those three in list order ($(cat "$out/several" 2>/dev/null))" answer_is several "$(chosen "$dl/f01.txt" "$dl/f02.txt" "$dl/f03.txt")"

ask toggle "$(request open "$dl" true)"
shown
rows_drawn
click_at picker-row:1
mod_at shift picker-row:3
until_ok 2000 state_is '.marked | length == 3'
mod_at ctrl picker-row:2
check "a Ctrl-click toggles one off ($(pk_state | jq -c '[.selected, .marked]'))" until_ok 2000 state_is '.selected == 2 and .marked == ["f01.txt", "f03.txt"]'
wtype -k Return
until_ok 3000 answered toggle
check "Enter on the unmarked cursor file answers only it ($(cat "$out/toggle" 2>/dev/null))" answer_is toggle "$(chosen "$dl/f02.txt")"

ask single "$(request open "$dl")"
shown
rows_drawn
click_at picker-row:1
mod_at shift picker-row:3
check "without multiple, a Shift-click selects and marks nothing ($(pk_state | jq -c '[.selected, .marked]'))" until_ok 2000 state_is '.selected == 3 and .marked == []'
mod_at ctrl picker-row:2
check "and a Ctrl-click marks nothing ($(pk_state | jq -c '[.selected, .marked]'))" until_ok 2000 state_is '.selected == 2 and .marked == []'
click_at picker-place:0
check "a click on a place opens it ($(pk_state | jq -c .folder))" until_ok 3000 state_is --arg f "$HOME" '.folder == $f and .listed'
finish single

# Nothing acts behind the path field.
ask path "$(request open "$dl")"
shown
rows_drawn
click_at picker-row:2
until_ok 2000 state_is '.selected == 2'
wtype -M ctrl -k l -m ctrl
until_ok 2000 state_is '.pathMode'
click_at picker-row:4
dclick_at picker-row:4
check "with the path field open, a click on a row changes nothing ($(pk_state | jq -c '[.pathMode, .selected, .folder]'))" state_is --arg f "$dl" '.pathMode and .selected == 2 and .folder == $f and .open'
check "and a double click answers nothing" unanswered path
click_at picker-place:0
check "nor does a click on a place open it" state_is --arg f "$dl" '.folder == $f'
wtype -k Escape
until_ok 2000 state_is '.pathMode == false'
finish path

# Nothing acts behind the replace question.
ask replace "$(request save "$docs" false report.pdf)"
shown
rows_drawn
wtype -k Return
until_ok 2000 state_is '.question'
click_at picker-row:0
dclick_at picker-row:0
check "with the replace question up, a click on a row changes nothing ($(pk_state | jq -c '[.question, .name, .selected]'))" state_is '.question and .name == "report.pdf" and .rows[.selected].name == "report.pdf" and .open'
check "and answers nothing" unanswered replace
click_at picker-place:0
check "nor does a click on a place open it" state_is --arg f "$docs" '.folder == $f'
wtype -k Escape
until_ok 2000 state_is '.question == false'
finish replace

# The wheel scrolls the list and leaves the cursor.
ask wheel "$(request open "$big")"
shown
until_ok 4000 bash -c "[ -n \"\$(timeout 0.5 qs ipc call shell box picker-row:8)\" ]"
before=$(shell_box picker-row:8 | jq .y)
wheel_box picker-row:3 3
scrolled() { [ "$(shell_box picker-row:8 | jq ".y < $before")" = true ]; }
check "the wheel over the list scrolls it, a later row moving up ($before to $(shell_box picker-row:8 | jq .y))" until_ok 2000 scrolled
check "and the cursor stays" state_is '.selected == 0'
finish wheel

errs=$(qml_errors)
check "the shell's journal has no QML errors${errs:+: $(head -c 200 <<<"$errs")}" test -z "$errs"

exit $((fails > 0))
}
