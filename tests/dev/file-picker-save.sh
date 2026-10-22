#!/usr/bin/env bash
# An app's save dialog on the shell's picker: the suggested name in an editable field, Enter answers the folder plus that name, and a name already there asks before replacing it.
{
source "$(dirname "$0")/lib.sh"

sock=$XDG_RUNTIME_DIR/dots-picker-$WAYLAND_DISPLAY.sock
fresh=$DOTS_DEV_DIR/save/fresh docs=$DOTS_DEV_DIR/save/docs out=$DOTS_DEV_DIR/answers
mkdir -p "$fresh/drafts" "$docs/drafts" "$out"
: >"$fresh/notes.md"
: >"$docs/notes.md"
truncate -s 184000 "$docs/report.pdf"

entry=/usr/share/applications/kak.desktop
app=$(sed -n 's/^Name=//p' "$entry" 2>/dev/null | head -1)
app=${app:-kak}

pk_state() { timeout 0.5 dots-call picker state 2>/dev/null; }
state_is() { pk_state | jq -e "$@" >/dev/null 2>&1; }
request() { jq -cn --arg folder "$1" --arg name "${2-report.pdf}" '{mode: "save", multiple: false, title: "Save As", app: "kak", folder: $folder, name: $name, filters: [], filter: 0, accept: ""}'; }
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
# Gives the picker 600 ms to answer what it must not.
unanswered() { ! until_ok 600 answered "$1"; }
shown() { until_ok 4000 state_is '.open and .settled and .listed'; }
erase() { local i; for i in $(seq 1 12); do wtype -k BackSpace; done; }

ask save "$(request "$fresh")"
shown
echo "     save: $(pk_state | jq -c '{mode, heading, name, focus, question, hint, rows: [.rows[] | [.name, .tag]], selected}')"
check "a save request opens in save mode with report.pdf in the name field" state_is '.mode == "save" and .name == "report.pdf" and .focus == "name"'
wtype -k Return
until_ok 3000 answered save
check "Enter answers the folder plus the name ($(cat "$out/save" 2>/dev/null))" answer_is save "{\"response\":0,\"paths\":[\"$fresh/report.pdf\"]}"

ask edit "$(request "$fresh")"
shown
erase
wtype "notes 2.txt"
check "the name field takes typed text, spaces kept ($(pk_state | jq -c .name))" until_ok 2000 state_is '.name == "notes 2.txt"'
wtype -k Return
until_ok 3000 answered edit
check "Enter answers the edited name ($(cat "$out/edit" 2>/dev/null))" answer_is edit "{\"response\":0,\"paths\":[\"$fresh/notes 2.txt\"]}"

ask replace "$(request "$docs")"
shown
check "the file already there holds the cursor and reads EXISTS ($(pk_state | jq -c '[.rows[.selected].name, .rows[.selected].tag]'))" state_is '.rows[.selected].name == "report.pdf" and (.rows[.selected].tag | test("exists"; "i"))'
wtype -k Return
until_ok 2000 state_is '.question'
check "Enter on a name that exists asks first ($(pk_state | jq -c '[.question, .hint]'))" state_is '.question and (.hint | test("report.pdf exists"; "i"))'
check "and does not answer" unanswered replace
wtype -k Escape
check "Esc keeps the file and returns to the name field" until_ok 2000 state_is '.open and (.question | not) and .focus == "name" and .name == "report.pdf"'
check "and answers nothing" unanswered replace
wtype -k Return
until_ok 2000 state_is '.question'
wtype -k Return
until_ok 3000 answered replace
check "Enter on the question answers the path ($(cat "$out/replace" 2>/dev/null))" answer_is replace "{\"response\":0,\"paths\":[\"$docs/report.pdf\"]}"

ask refuse "$(request "$fresh")"
shown
erase
until_ok 2000 state_is '.name == ""'
wtype -k Return
check "an empty name does not answer ($(pk_state | jq -c .hint))" unanswered refuse
check "and says why" state_is '.open and .notice == "empty"'
wtype "a/b.txt"
until_ok 2000 state_is '.name == "a/b.txt"'
wtype -k Return
check "a name with / does not answer ($(pk_state | jq -c .hint))" unanswered refuse
check "and says why" state_is '.open and .notice == "slash"'
wtype -k Escape
until_ok 3000 answered refuse
check "Esc in the name field answers a cancel ($(cat "$out/refuse" 2>/dev/null))" answer_is refuse '{"response":1,"paths":[]}'

# ctrl+l still types a path in save mode; an Enter sent with the path goes there once the path's folder is listed, and the name stays.
for i in 1 2 3 4 5; do
  ask "path-$i" "$(request "$fresh")"
  shown
  wtype -M ctrl l -m ctrl
  until_ok 2000 state_is '.pathMode'
  wtype "$docs/drafts/" -k Return
  check "run $i: a path typed with Enter at once enters it ($(until_ok 2000 state_is '.pathMode == false'; pk_state | jq -c '[.folder, .pathMode, .name]'))" until_ok 2000 state_is --arg f "$docs/drafts" '.folder == $f and .pathMode == false and .name == "report.pdf"'
  wtype -k Escape
  until_ok 1000 state_is '.pathMode == false'
  wtype -k Escape
  until_ok 3000 answered "path-$i"
done

# Each theme writes the heading and the question in its voice; the file's name keeps its case.
status_theme() { shell_status | jq -e --arg t "$1" '.theme == $t' >/dev/null; }
in_theme() { "$repo/bin/dots" theme "$1" >/dev/null; until_ok 2000 status_theme "$1"; }
for t in "paper|SAVE AS · ${app^^}|report.pdf exists · ↵ REPLACE · ESC KEEP" \
  "artboard|Save as · $app|report.pdf exists · ↵ replace · esc keep" \
  "blueprint|SAVE AS // ${app^^}|! report.pdf EXISTS · [↵] REPLACE · [ESC] KEEP"; do
  IFS='|' read -r name heading question <<<"$t"
  in_theme "$name"
  ask "theme-$name" "$(request "$docs")"
  shown
  check "$name: the heading reads $heading and the field report.pdf ($(pk_state | jq -c '[.heading, .name]'))" state_is --arg h "$heading" '.heading == $h and .name == "report.pdf"'
  wtype -k Return
  until_ok 2000 state_is '.question'
  check "$name: the question reads $question ($(pk_state | jq -c .hint))" state_is --arg q "$question" '.hint == $q'
  wtype -k Escape
  until_ok 2000 state_is '.question | not'
  wtype -k Escape
  until_ok 3000 answered "theme-$name"
done

exit $((fails > 0))
}
