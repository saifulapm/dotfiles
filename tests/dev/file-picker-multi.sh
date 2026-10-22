#!/usr/bin/env bash
# An app that allows several files marks them with ctrl+space and opens them all with ctrl+Enter; an app that asks for a folder sees only folders and chooses the one it is in.
{
source "$(dirname "$0")/lib.sh"

sock=$XDG_RUNTIME_DIR/dots-picker-$WAYLAND_DISPLAY.sock
dl=$DOTS_DEV_DIR/multi/Downloads pick=$DOTS_DEV_DIR/multi/pick out=$DOTS_DEV_DIR/answers
mkdir -p "$dl/screenshots" "$pick/Codes/lareys" "$pick/Codes/scratch" "$pick/music" "$out"
for n in IMG_2039.HEIC IMG_2040.HEIC IMG_2041.HEIC notes.txt; do truncate -s 2800000 "$dl/$n"; done
: >"$pick/a.txt"
: >"$pick/b.pdf"
: >"$pick/Codes/README.md"

entry=/usr/share/applications/chromium-browser.desktop
app=$(sed -n 's/^Name=//p' "$entry" 2>/dev/null | head -1)
app=${app:-chromium-browser}

pk_state() { timeout 0.5 dots-call picker state 2>/dev/null; }
state_is() { pk_state | jq -e "$@" >/dev/null 2>&1; }
request() { jq -cn --arg mode "$1" --arg folder "$2" --argjson multiple "${3-false}" '{mode: $mode, multiple: $multiple, title: "", app: "chromium-browser", folder: $folder, name: "", filters: [], filter: 0, accept: ""}'; }
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
chosen() { jq -cn '{response: 0, paths: $ARGS.positional}' --args "$@"; }
shown() { until_ok 4000 state_is '.open and .settled and .listed'; }
cursor_to() {
  local i
  for i in 1 2 3 4 5 6; do
    until_ok 300 state_is --arg n "$1" '.rows[.selected].name == $n' && return 0
    wtype -k Down
  done
  return 1
}
mark() { wtype -M ctrl -k space -m ctrl; }
marks() { pk_state | jq -c '[.marked, [.rows[] | select(.marked) | .name], .foot]'; }

ask several "$(request open "$dl" true)"
shown
check "an app that allows several files heads the card Open files ($(pk_state | jq -c .heading))" state_is '.heading | test("^open files"; "i")'
mark
check "ctrl+space on a folder marks nothing ($(marks))" until_ok 600 state_is '.rows[.selected].name == "screenshots/" and .marked == [] and .foot == ""'
cursor_to IMG_2041.HEIC
mark
until_ok 1000 state_is '.marked | length == 1'
wtype -k Up -k Up
until_ok 1000 state_is '.rows[.selected].name == "IMG_2039.HEIC"'
mark
until_ok 1000 state_is '.marked | length == 2'
# The query narrows the list to one file; the marks it hides stay.
wtype 2040
until_ok 1000 state_is '[.rows[].name] == ["IMG_2040.HEIC"]'
mark
until_ok 1000 state_is '.marked | length == 3'
wtype -k BackSpace -k BackSpace -k BackSpace -k BackSpace
until_ok 1000 state_is '.rows | length == 5'
check "three marked files draw as marked and read 3 selected below the list ($(marks))" state_is '(.marked | sort) == ["IMG_2039.HEIC", "IMG_2040.HEIC", "IMG_2041.HEIC"] and [.rows[] | select(.marked) | .name] == ["IMG_2039.HEIC", "IMG_2040.HEIC", "IMG_2041.HEIC"] and (.foot | test("^3 selected"; "i"))'
wtype -M ctrl -k Return -m ctrl
until_ok 3000 answered several
check "ctrl+Enter answers the three, in list order ($(cat "$out/several" 2>/dev/null))" answer_is several "$(chosen "$dl/IMG_2039.HEIC" "$dl/IMG_2040.HEIC" "$dl/IMG_2041.HEIC")"

ask one "$(request open "$dl" true)"
shown
cursor_to IMG_2039.HEIC
mark
wtype -k Down
mark
until_ok 1000 state_is '.marked | length == 2'
cursor_to notes.txt
wtype -k Return
until_ok 3000 answered one
check "with files marked, Enter answers only the cursor file ($(cat "$out/one" 2>/dev/null))" answer_is one "$(chosen "$dl/notes.txt")"

ask single "$(request open "$dl")"
shown
cursor_to IMG_2041.HEIC
mark
check "without multiple, ctrl+space marks nothing ($(marks))" until_ok 600 state_is '.marked == [] and ([.rows[] | select(.marked)] | length) == 0 and .foot == ""'
check "and the heading stays Open file ($(pk_state | jq -c .heading))" state_is '.heading | test("^open file( |$)"; "i")'
wtype -k Escape
until_ok 3000 answered single

ask folder "$(request folder "$pick")"
shown
echo "     folder: $(pk_state | jq -c '{heading, count, rows: [.rows[] | [.name, .size]], previewShown, foot, hint}')"
check "a folder request lists only the folders, no files" state_is '[.rows[].name] == ["Codes/", "music/"] and ([.rows[] | select(.dir | not)] | length) == 0 and (.previewShown | not)'
wtype -k Return
check "Enter enters the folder under the cursor, which lists only its folders ($(pk_state | jq -c '[.folder, [.rows[].name]]'))" until_ok 2000 state_is --arg f "$pick/Codes" '.folder == $f and .listed and [.rows[].name] == ["lareys/", "scratch/"]'
check "the footer names the folder ctrl+Enter chooses ($(pk_state | jq -c .foot))" state_is '.foot | test("Codes")'
wtype -M ctrl -k Return -m ctrl
until_ok 3000 answered folder
check "ctrl+Enter answers the folder the picker is in ($(cat "$out/folder" 2>/dev/null))" answer_is folder "$(chosen "$pick/Codes")"

# Enter and ctrl+Enter in one wtype call: ctrl+Enter answers the folder Enter went into, its listing still running.
for i in 1 2 3 4 5; do
  ask "fast-$i" "$(request folder "$pick")"
  shown
  wtype -k Return -M ctrl -k Return -m ctrl
  until_ok 3000 answered "fast-$i"
  check "run $i: Enter then ctrl+Enter at once answers Codes ($(cat "$out/fast-$i" 2>/dev/null))" answer_is "fast-$i" "$(chosen "$pick/Codes")"
done

# Each theme heads both cards in its voice and writes the folder strip.
status_theme() { shell_status | jq -e --arg t "$1" '.theme == $t' >/dev/null; }
in_theme() { "$repo/bin/dots" theme "$1" >/dev/null; until_ok 2000 status_theme "$1"; }
for t in "paper|OPEN FILES · ${app^^}|CHOOSE FOLDER · ${app^^}|↵ ENTER FOLDER · ⌃↵ CHOOSE THIS FOLDER · ESC" \
  "artboard|Open files · $app|Choose folder · $app|↵ enter folder · ctrl+↵ choose this folder · esc" \
  "blueprint|OPEN FILES // ${app^^}|CHOOSE FOLDER // ${app^^}|[↵] ENTER FOLDER · [⌃↵] CHOOSE THIS FOLDER · [ESC]"; do
  IFS='|' read -r name multi folder strip <<<"$t"
  in_theme "$name"
  ask "multi-$name" "$(request open "$dl" true)"
  shown
  check "$name: several files head the card $multi ($(pk_state | jq -c .heading))" state_is --arg h "$multi" '.heading == $h'
  wtype -k Escape
  until_ok 3000 answered "multi-$name"
  ask "folder-$name" "$(request folder "$pick")"
  shown
  check "$name: a folder request heads the card $folder and keys $strip ($(pk_state | jq -c '[.heading, .hint]'))" state_is --arg h "$folder" --arg s "$strip" '.heading == $h and .hint == $s'
  wtype -k Escape
  until_ok 3000 answered "folder-$name"
done

exit $((fails > 0))
}
