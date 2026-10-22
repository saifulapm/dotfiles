#!/usr/bin/env bash
# Finding a file in the shell's picker: a typed query narrows places or rows, Tab walks the places, ctrl+l types a path, ctrl+h shows dotfiles, an app's filters hide files, and an image previews.
{
source "$(dirname "$0")/lib.sh"

sock=$XDG_RUNTIME_DIR/dots-picker-$WAYLAND_DISPLAY.sock
dl=$DOTS_DEV_DIR/Downloads codes=$DOTS_DEV_DIR/Codes out=$DOTS_DEV_DIR/answers
mkdir -p "$dl/screenshots" "$out" "$codes/lareys" "$codes/lareys-mobile" "$codes/laravel-demo" "$codes/dotfiles"
truncate -s 3100000 "$dl/IMG_2041.HEIC"
truncate -s 184000 "$dl/report-october.pdf"
# A real 640 x 480 PNG, so Qt has something to decode.
python3 -c '
import struct, sys, zlib
w, h = 640, 480
raw = b"".join(b"\0" + b"\x30\x60\x90" * w for _ in range(h))
ch = lambda t, d: struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d))
open(sys.argv[1], "wb").write(b"\x89PNG\r\n\x1a\n" + ch(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)) + ch(b"IDAT", zlib.compress(raw)) + ch(b"IEND", b""))
' "$dl/shot.png"
# Recent first means lareys, then lareys-mobile, then laravel-demo.
touch -d '2026-10-18 12:00' "$codes/lareys"
touch -d '2026-10-03 12:00' "$codes/lareys-mobile"
touch -d '2026-09-09 12:00' "$codes/laravel-demo"
touch -d '2026-10-20 12:00' "$codes/dotfiles"

pk_state() { timeout 0.5 dots-call picker state 2>/dev/null; }
state_is() { pk_state | jq -e "$@" >/dev/null 2>&1; }
request() { jq -cn --arg folder "$1" --argjson filters "${2-[]}" '{mode: "open", multiple: false, title: "Open File", app: "chromium-browser", folder: $folder, name: "", filters: $filters, filter: 0, accept: ""}'; }
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
shown() { until_ok 4000 state_is '.open and .settled and .listed'; }
listed_in() { until_ok 3000 state_is --arg f "$1" '.folder == $f and .listed'; }
cancel() { wtype -k Escape; until_ok 3000 answered "$1"; }
plain_names() { jq -c '[.completions[].name | gsub("<[^>]*>"; "")]'; }
# Down until the cursor row is a file.
cursor_to_file() {
  local i
  for i in $(seq 1 40); do
    until_ok 300 state_is '.rows[.selected].dir == false' && return 0
    wtype -k Down
  done
  return 1
}
cursor_to() {
  local i
  for i in 1 2 3 4 5 6; do
    until_ok 300 state_is --arg n "$1" '.rows[.selected].name == $n' && return 0
    wtype -k Down
  done
  return 1
}
dl_files=$(python3 -c 'import os, sys; print(sum(1 for e in os.scandir(sys.argv[1]) if not e.name.startswith(".")))' "$HOME/Downloads")

# A query that matches one place opens it, unfiltered.
ask place "$(request "$dl")"
shown
wtype down
listed_in "$HOME/Downloads"
echo "     typed: $(pk_state | jq -c '{typed, match, matches, folder, rows: (.rows | length)}')"
check "typing down leaves Downloads the only matching place, underlined" state_is '.matches == ["<u>Down</u>loads"]'
check "and opens Downloads" state_is --arg f "$HOME/Downloads" '.folder == $f'
check "its list unfiltered ($dl_files rows)" state_is --arg n "$dl_files ITEMS" '.count | startswith($n)'
wtype -k Down
cursor_to_file
want=$(pk_state | jq -r --arg f "$HOME/Downloads" '$f + "/" + .rows[.selected].name')
wtype -k Return
until_ok 3000 answered place
check "Down then Enter answers a file in Downloads ($(cat "$out/place" 2>/dev/null))" bash -c "jq -e --arg p \"\$1\" '.response == 0 and .paths == [\$p]' '$out/place' >/dev/null" _ "$want"

# A query that matches no place filters the rows; Backspace widens them again.
ask query "$(request "$dl")"
shown
wtype 2041
until_ok 2000 state_is '.typed | endswith("2041")'
check "2041 matches no place and leaves only IMG_2041.HEIC ($(pk_state | jq -c '[.typed, [.rows[].name]]'))" state_is '.matches == [] and [.rows[].name] == ["IMG_2041.HEIC"]'
wtype -k BackSpace -k BackSpace -k BackSpace -k BackSpace
check "Backspace erases the query and every row is back" until_ok 2000 state_is --arg f "$dl" '.folder == $f and (.rows | length) == 4'
cancel query

# Tab walks to the places and back.
ask tab "$(request "$dl")"
shown
wtype -k Tab
check "Tab moves the cursor to the places" until_ok 2000 state_is '.focus == "places"'
wtype -k Down -k Return
listed_in "$HOME/Downloads"
check "Down and Enter there open Downloads" state_is --arg f "$HOME/Downloads" '.folder == $f and .open'
wtype -k Tab
check "Tab returns to the list" until_ok 2000 state_is '.focus == "list"'
cancel tab

# ctrl+l types a path and completes to folders.
ask path "$(request "$dl")"
shown
wtype -M ctrl l -m ctrl
until_ok 2000 state_is '.pathMode'
wtype "$codes/la"
until_ok 3000 state_is '(.completions | length) == 3'
echo "     path: $(pk_state | jq -c '{typed, prompt, match, completionHead, completions, hint, preview: .previewShown}')"
check "the completions are the folders starting with la, recent first" bash -c "[ \"\$(timeout 0.5 dots-call picker state | jq -c '[.completions[].name | gsub(\"<[^>]*>\"; \"\")]')\" = '[\"$codes/lareys/\",\"$codes/lareys-mobile/\",\"$codes/laravel-demo/\"]' ]"
check "each with la underlined" state_is '.completions[0].name | endswith("/<u>la</u>reys/")'
check "the first holds the cursor and the preview hides" state_is '.choice == 0 and .previewShown == false'
wtype -k Tab
check "Tab completes to it" until_ok 2000 state_is --arg p "$codes/lareys/" '.typed == $p'
wtype -k Return
check "Enter enters the folder" until_ok 3000 state_is --arg f "$codes/lareys" '.folder == $f and .listed and .pathMode == false'
check "and answers nothing" eval '! answered path'
wtype -k BackSpace
check "Backspace with no query goes up, the cursor on the folder it left" until_ok 3000 state_is --arg f "$codes" '.folder == $f and .listed and .rows[.selected].name == "lareys/"'
wtype -M ctrl l -m ctrl
until_ok 2000 state_is '.pathMode'
wtype -M ctrl l -m ctrl
check "ctrl+l again returns to the list" until_ok 2000 state_is '.pathMode == false and .open'
wtype -M ctrl l -m ctrl
until_ok 2000 state_is '.pathMode'
wtype '~/Cod'
check "~ expands to Home: ~/Cod completes to Codes" until_ok 3000 state_is '.completions | any(.[]; .name == "~/<u>Cod</u>es/")'
wtype -k Escape
check "Esc returns to the list without answering" until_ok 2000 state_is '.pathMode == false and .open'
check "and nothing is answered" eval '! answered path'
cancel path

# ctrl+h shows dotfiles.
ask hidden "$(request "$HOME")"
shown
check "Home hides .config at first, and says so ($(pk_state | jq -c .count))" state_is '(any(.rows[]; .name == ".config/") | not) and (.count | endswith("HIDDEN OFF"))'
wtype -M ctrl h -m ctrl
check "ctrl+h shows .config" until_ok 2000 state_is 'any(.rows[]; .name == ".config/") and (.count | endswith("HIDDEN ON"))'
wtype -M ctrl h -m ctrl
check "ctrl+h again hides it" until_ok 2000 state_is '(any(.rows[]; .name == ".config/") | not) and (.count | endswith("HIDDEN OFF"))'
cancel hidden

# The cursor file previews when Qt decodes it.
ask preview "$(request "$dl")"
shown
cursor_to IMG_2041.HEIC
check "a HEIC does not preview, and still reads its size and date" until_ok 2000 state_is '.preview == false and .previewName == "IMG_2041.HEIC" and .previewLines[0] == {label: "SIZE", value: "3.1 MB"} and .previewLines[1].label == "MODIFIED"'
cursor_to report-october.pdf
check "nor does a PDF ($(pk_state | jq -c '[.preview, .previewLines]'))" until_ok 2000 state_is '.preview == false and .previewName == "report-october.pdf" and .previewLines[0] == {label: "SIZE", value: "184 KB"} and .previewDims == ""'
cursor_to shot.png
check "a PNG under the cursor previews at its size ($(until_ok 2000 state_is .preview; pk_state | jq -c '[.preview, .previewName, .previewLines]'))" until_ok 2000 state_is '.preview and .previewDims == "640 × 480" and .previewName == "shot.png"'
cancel preview

# An app's filters hide files and cycle.
ask filters "$(request "$dl" '[{"name":"Images","globs":["*.png","*.jpg"],"mimes":[]},{"name":"All","globs":["*"],"mimes":[]}]')"
shown
check "the Images filter hides the PDF and names itself ($(pk_state | jq -c '[.count, [.rows[].name]]'))" state_is '[.rows[].name] == ["screenshots/", "shot.png"] and (.count | test("IMAGES"))'
wtype -M shift -k Tab -m shift
check "shift+tab switches to All and the PDF shows" until_ok 2000 state_is 'any(.rows[]; .name == "report-october.pdf") and (.count | test("ALL"))'
cancel filters

# Each theme writes the match and the path mode in its own voice.
status_theme() { shell_status | jq -e --arg t "$1" '.theme == $t' >/dev/null; }
in_theme() { "$repo/bin/dots" theme "$1" >/dev/null; until_ok 2000 status_theme "$1"; }
for t in "paper|1 PLACE|PATH|3 MATCHES|FOLDERS|↵ GO · TAB COMPLETE · ⌃L BACK TO LIST · ESC|$codes/lareys/" \
  "artboard|→ Downloads|path||3 folders in $codes start with la|tab complete · ↵ go · ctrl+l filter · esc|lareys" \
  "blueprint|1 PLACE|> PATH|3 MATCHES|COMPLETING IN $codes|[↵] GO · [TAB] COMPLETE · [⌃L] BACK TO LIST · [ESC]|lareys/"; do
  IFS='|' read -r name match prompt count head hint first <<<"$t"
  in_theme "$name"
  ask "theme-$name" "$(request "$dl")"
  shown
  wtype down
  listed_in "$HOME/Downloads"
  check "$name: down reads $match beside the query ($(pk_state | jq -c '[.typed, .match, .matches]'))" state_is --arg m "$match" '.match == $m'
  wtype -M ctrl l -m ctrl
  until_ok 2000 state_is '.pathMode'
  wtype "$codes/la"
  until_ok 3000 state_is '(.completions | length) == 3'
  check "$name: the path mode reads $prompt, '$count', $head ($(pk_state | jq -c '[.prompt, .typed, .match, .completionHead, .count]'))" state_is --arg p "$prompt" --arg c "$count" --arg h "$head" '.prompt == $p and .match == $c and .completionHead == $h'
  check "$name: the first completion reads $first, real case" state_is --arg f "$first" '(.completions[0].name | gsub("<[^>]*>"; "")) == $f'
  check "$name: the keys read $hint" state_is --arg k "$hint" '.hint == $k'
  wtype -k Escape
  until_ok 2000 state_is '.pathMode == false'
  cancel "theme-$name"
done

exit $((fails > 0))
}
