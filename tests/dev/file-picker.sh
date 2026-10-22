#!/usr/bin/env bash
# An app's open dialog on the shell's own picker: the check plays bin/dots-portal on the picker socket, one request line per connection and one answer line back.
{
source "$(dirname "$0")/lib.sh"

sock=$XDG_RUNTIME_DIR/dots-picker-$WAYLAND_DISPLAY.sock
dl=$DOTS_DEV_DIR/Downloads forged=$DOTS_DEV_DIR/forged out=$DOTS_DEV_DIR/answers
mkdir -p "$dl/screenshots" "$forged" "$out"
truncate -s 3100000 "$dl/IMG_2041.HEIC"
truncate -s 184000 "$dl/report-october.pdf"
# Spaces, # and % would come back changed through any URI or percent step, and ü through any byte-wise one.
odd='a b #1 %41 ü.txt'
: >"$dl/$odd"
touch "$dl/screenshots/one.png" "$dl/screenshots/two.png" "$dl/screenshots/three.png" "$dl/.hidden"
long=$(printf 'n%.0s' $(seq 200))
for n in $'two\nlines.txt' $'rtl‮txt.exe' $'esc\e[31mred.txt' "$long.txt"; do : >"$forged/$n"; done

entry=/usr/share/applications/chromium-browser.desktop
app=$(sed -n 's/^Name=//p' "$entry" 2>/dev/null | head -1)
app=${app:-chromium-browser}

pk_state() { timeout 0.5 dots-call picker state 2>/dev/null; }
state_is() { pk_state | jq -e "$@" >/dev/null 2>&1; }
focus_is() { niri msg -j layers | jq -e --arg k "$1" 'any(.[]; .namespace == "dots-surfaces" and .keyboard_interactivity == $k)' >/dev/null; }
request() { jq -cn --arg folder "$1" --arg app "${2-chromium-browser}" --arg title "${3-Open File}" '{mode: "open", multiple: false, title: $title, app: $app, folder: $folder, name: "", filters: [], filter: 0, accept: ""}'; }
# Writes one line and holds the connection open; whatever the shell sends lands in $out/<tag> when the shell closes it. Not in a subshell, so its pid stays this shell's child.
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
shown() { until_ok 4000 state_is '.open and .settled and .listed'; }
cursor_to() {
  local i
  for i in 1 2 3 4 5 6; do
    until_ok 300 state_is --arg n "$1" '.rows[.selected].name == $n' && return 0
    wtype -k Down
  done
  return 1
}

check "before any request the picker is not loaded" state_is '.loaded == false'

ask first "$(request "$dl")"
shown
echo "     picker: $(pk_state | jq -c '{mode, app, heading, folder, path, count, rows: [.rows[] | [.name, .size, .modified]], places, hint}')"
check "a request opens the picker in open mode for $app, holding the keyboard" state_is --arg app "$app" '.mode == "open" and .app == $app and .keyboard'
check "and the card has the keyboard" focus_is Exclusive
check "the open is timed from the request line to the first frame ($(pk_state | jq -c '[.openMs, .opens]'))" state_is '.openMs > 0 and .opens == 1'
check "it lists the folder's rows, folders first, without dotfiles" state_is --arg odd "$odd" '.folder == "'"$dl"'" and [.rows[].name] == ["screenshots/", $odd, "IMG_2041.HEIC", "report-october.pdf"]'
check "a folder counts its items and a file reads its size" state_is '.rows[0].size == "3 items" and .rows[2].size == "3.1 MB" and .rows[3].size == "184 KB"'

cursor_to IMG_2041.HEIC
wtype -k Return
until_ok 3000 answered first
check "Enter on IMG_2041.HEIC answers its path ($(cat "$out/first" 2>/dev/null))" answer_is first "{\"response\":0,\"paths\":[\"$dl/IMG_2041.HEIC\"]}"
check "and the picker closes" until_ok 3000 state_is '.open == false'

ask esc "$(request "$dl")"
shown
wtype -k Escape
until_ok 3000 answered esc
check "Esc answers a cancel ($(cat "$out/esc" 2>/dev/null))" answer_is esc '{"response":1,"paths":[]}'

ask dirs "$(request "$dl")"
shown
wtype -k Return
until_ok 3000 state_is '.folder == "'"$dl/screenshots"'" and .listed'
check "Enter on a folder enters it ($(pk_state | jq -c '[.folder, [.rows[].name]]'))" state_is '.open and .folder == "'"$dl/screenshots"'" and [.rows[].name] == ["one.png", "three.png", "two.png"]'
check "and does not answer" eval '! answered dirs'
wtype -k Left
until_ok 3000 state_is '.folder == "'"$dl"'" and .listed'
check "Left goes back to the parent" state_is '.open and .folder == "'"$dl"'"'

cursor_to "$odd"
wtype -k Return
until_ok 3000 answered dirs
check "a name with spaces, #, % and ü comes back byte for byte ($(cat "$out/dirs" 2>/dev/null))" bash -c "jq -e --arg p '$dl/$odd' '.response == 0 and .paths == [\$p]' '$out/dirs' >/dev/null"

# Two at once: the second waits, and each answer reaches its own connection.
ask one "$(request "$dl")"
shown
ask two "$(request "$dl/screenshots")"
until_ok 3000 state_is '.waiting == 1'
check "a second request waits while the first shows" state_is '.open and .waiting == 1 and .folder == "'"$dl"'"'
cursor_to IMG_2041.HEIC
wtype -k Return
until_ok 3000 answered one
check "the first answer goes to the first connection only" bash -c "[ \"\$(jq -r '.paths[0]' '$out/one')\" = '$dl/IMG_2041.HEIC' ] && [ ! -e '$out/two' ]"
until_ok 3000 state_is '.open and .settled and .listed and .waiting == 0 and .folder == "'"$dl/screenshots"'"'
check "then the second shows" state_is '.open and .waiting == 0 and .folder == "'"$dl/screenshots"'"'
wtype -k Escape
until_ok 3000 answered two
check "and its cancel goes to it" answer_is two '{"response":1,"paths":[]}'

# The app gives up: a shown request's card closes, a waiting one leaves the queue.
ask gone "$(request "$dl")"
shown
kill "$pid"
check "a shown request whose client hangs up closes the card" until_ok 3000 state_is '.open == false and .waiting == 0'
ask stay "$(request "$dl")"
shown
ask left "$(request "$dl")"
until_ok 3000 state_is '.waiting == 1'
kill "$pid"
check "a waiting request whose client hangs up leaves the queue" until_ok 3000 state_is '.open and .waiting == 0'
wtype -k Escape
until_ok 3000 answered stay
check "and the shown one still answers its own connection" answer_is stay '{"response":1,"paths":[]}'

ask bad 'not a request {'
until_ok 3000 answered bad
check "a malformed request line gets response 2 ($(cat "$out/bad" 2>/dev/null))" answer_is bad '{"response":2,"paths":[]}'
check "and opens nothing" state_is '.open == false'

# Text the app or the folder controls draws on one line and is cut short.
ask forged "$(request "$forged" $'evil\napp‮\e[31m'"$long" $'two\nline‮ title\e[0m')"
shown
echo "     forged: $(pk_state | jq -c '{app, title, heading, headingTruncated, rows: [.rows[] | [.name[0:30], .lines, .elided]]}')"
check "the app id and title read as one line without controls or bidi marks" state_is '[.app, .title, .heading] | all(.[]; test("[\n\u001b\u202e]") | not)'
check "the 200-character app id is cut short in a one-line heading" state_is '.headingTruncated and .headingLines == 1'
check "file names draw on one line without controls or bidi marks" state_is '[.rows[].name] | all(.[]; test("[\n\u001b\u202e]") | not)'
check "every forged row is one line, the 200-character one cut short" state_is '(.rows | length) == 4 and all(.rows[]; .lines == 1) and any(.rows[]; .elided and (.name | startswith("nnnn")))'
wtype -k Escape
until_ok 3000 answered forged
ask bare "$(request "$dl" '' '')"
shown
check "a request with no app reads just Open file ($(pk_state | jq -c .heading))" state_is '.heading == "OPEN FILE"'
wtype -k Escape
until_ok 3000 answered bare

# Each theme writes the heading in its voice; Blueprint's caps are for labels, never for file names.
status_theme() { shell_status | jq -e --arg t "$1" '.theme == $t' >/dev/null; }
in_theme() { "$repo/bin/dots" theme "$1" >/dev/null; until_ok 2000 status_theme "$1"; }
for t in "paper|OPEN FILE · ${app^^}" "artboard|Open file · $app" "blueprint|OPEN FILE // ${app^^}"; do
  IFS='|' read -r name heading <<<"$t"
  in_theme "$name"
  ask "theme-$name" "$(request "$dl")"
  shown
  check "$name: the heading reads $heading ($(pk_state | jq -c '[.heading, .hint]'))" state_is --arg h "$heading" '.heading == $h'
  check "$name: IMG_2041.HEIC is drawn in its real case" state_is 'any(.rows[]; .name == "IMG_2041.HEIC")'
  wtype -k Escape
  until_ok 3000 answered "theme-$name"
done

until_ok 3000 state_is '.drawing == false'
check "the picker is still loaded right after it closes" state_is '.loaded'
until_ok 33000 state_is '.loaded == false'
check "and unloaded 30 s later" state_is '.loaded == false'

exit $((fails > 0))
}
