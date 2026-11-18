#!/usr/bin/env bash
# The portal's file picker takes the island over as board 9 at 960 px: Chromium's header, the five places then the bookmarks, path pills, Open N, a save field with Keep and a red Replace, Choose this folder; the app hanging up hands back the launcher with its query, and a click on the paper takes one Esc level.
{
source "$(dirname "$0")/lib.sh"
source "$(dirname "$0")/pointer.bash"

sock=$XDG_RUNTIME_DIR/dots-picker-$WAYLAND_DISPLAY.sock
here=$DOTS_DEV_DIR/island-picker out=$DOTS_DEV_DIR/answers
mkdir -p "$here/open/shots" "$here/fresh" "$here/docs" "$here/pick/Codes/lareys" "$here/pick/music" "$out"
: >"$here/open/shots/one.png"
for n in a.txt b.txt c.txt; do : >"$here/open/$n"; done
: >"$here/fresh/notes.md"
: >"$here/docs/report.pdf"
: >"$here/pick/notes.txt"
# Chromium sends no app id, so the portal names the focused window; a chromium entry stands in for it.
printf '[Desktop Entry]\nType=Application\nName=Chromium\nIcon=chromium-browser\nExec=true\n' >"$DOTS_DEV_DIR/data/applications/chromium.desktop"

island() { timeout 0.5 qs ipc call island state 2>/dev/null; }
island_is() { island | jq -e "$@" >/dev/null 2>&1; }
launcher() { timeout 0.5 qs ipc call launcher state 2>/dev/null; }
launcher_is() { launcher | jq -e "$@" >/dev/null 2>&1; }
pk_state() { timeout 0.5 dots-call picker state 2>/dev/null; }
state_is() { pk_state | jq -e "$@" >/dev/null 2>&1; }
request() { jq -cn --arg mode "$1" --arg folder "$2" --argjson multiple "${3-false}" --arg name "${4-}" '{mode: $mode, multiple: $multiple, title: "", app: "chromium", folder: $folder, name: $name, filters: [], filter: 0, accept: ""}'; }
# Writes one line and holds the connection open; whatever the shell sends lands in $out/<tag> when the shell closes it.
ask() {
  rm -f "$out/$1"
  node -e '
    const [sock, line, file] = process.argv.slice(1), chunks = [];
    const s = require("net").connect(sock, () => s.write(line + "\n"));
    s.on("data", (d) => chunks.push(d));
    s.on("close", () => require("fs").writeFileSync(file, Buffer.concat(chunks)));
  ' "$sock" "$2" "$out/$1" 9>&- &
  pid=$!
}
answered() { [ -e "$out/$1" ]; }
answer_is() { [ "$(cat "$out/$1")" = "$2" ]; }
unanswered() { ! until_ok 800 answered "$1"; }
chosen() { jq -cn '{response: 0, paths: $ARGS.positional}' --args "$@"; }
shown() { until_ok 4000 state_is '.open and .settled and .keyboard and .listed'; }
cancel() { wtype -k Escape; until_ok 3000 answered "$1"; }
cursor_to() {
  local i
  for i in 1 2 3 4 5 6; do
    until_ok 300 state_is --arg n "$1" '.rows[.selected].name == $n' && return 0
    wtype -k Down
  done
  return 1
}
buttons() { pk_state | jq -c '[.buttons[] | [.text, .inverted]]'; }
rest() { island_is '.surface == null and .takeover == null and .animating == false'; }
read -r ow oh < <(niri msg -j outputs | jq -r '.[] | .logical | "\(.width) \(.height)"')

# 1. An open request from chromium takes the island over at 960 px.
ask open "$(request open "$here/open")"
shown
until_ok 5000 state_is '.heading == "Chromium wants to open files"'
echo "     picker: $(pk_state | jq -c '{heading, chip, places, pills, foot, buttons, width}') island: $(island | jq -c '{surface, takeover, width}')"
check "an open request from chromium sets takeover to picker ($(island | jq -c '{surface, takeover}'))" island_is '.takeover == "picker"'
check "the island is 960 px wide for it ($(island | jq .width))" island_is '.width == 960'
check "the header reads Chromium wants to open files ($(pk_state | jq -c .heading))" state_is '.heading == "Chromium wants to open files"'

# 5. The places: the five, then the bookmarks, and no drives.
pins=$(grep -c '^file://' "${XDG_CONFIG_HOME:-$HOME/.config}/gtk-3.0/bookmarks" 2>/dev/null)
check "the places are Home, Downloads, Documents, Pictures, Codes, then the ${pins:-0} bookmarks and no drives ($(pk_state | jq -c .places))" \
  state_is --argjson pins "${pins:-0}" '.places[0:5] == ["Home", "Downloads", "Documents", "Pictures", "Codes"] and (.places | length) == 5 + $pins'

# 2. Enter on a folder adds a pill; Enter on a file answers it.
check "the path outside Home draws as pills from / ($(pk_state | jq -c .pills))" state_is --arg p "$here/open" '.pills == ["/"] + ($p | ltrimstr("/") | split("/"))'
pills=$(pk_state | jq '.pills | length')
cursor_to shots/
wtype -k Return
until_ok 3000 state_is --arg f "$here/open/shots" '.folder == $f and .listed'
check "Enter on a folder enters it and the path gains a pill ($(pk_state | jq -c '[.folder, .pills]'))" state_is --argjson n "$pills" '(.pills | length) == $n + 1 and .pills[-1] == "shots"'
check "and answers nothing" unanswered open
cursor_to one.png
wtype -k Return
until_ok 3000 answered open
check "Enter on a file answers the app with it ($(cat "$out/open" 2>/dev/null))" answer_is open "$(chosen "$here/open/shots/one.png")"
until_ok 3000 rest

ask down "$(request open "$here/open")"
shown
# The last request's cursor sat on shots/one.png; the new folder has no such file, and nothing may ask for its size.
check "reopening in another folder measures no file from the last one ($(journalctl --user -u "$DOTS_DEV_UNIT" --no-pager -o cat | grep -c 'unhandled Python exception'))" bash -c '! journalctl --user -u "$DOTS_DEV_UNIT" --no-pager -o cat | grep -q "unhandled Python exception"'
wtype down
until_ok 3000 state_is --arg f "$HOME/Downloads" '.folder == $f and .listed'
check "typing down fills the filter field and narrows the places to Downloads, which opens ($(pk_state | jq -c '[.typed, .matches, .folder]'))" \
  state_is --arg f "$HOME/Downloads" '.typed == "down" and .matches == ["<u>Down</u>loads"] and .folder == $f'
check "under Home the path's pills start at ~ ($(pk_state | jq -c .pills))" state_is '.pills == ["~", "Downloads"]'
cancel down
until_ok 3000 rest

# 3. Three marked files: 3 selected and Open 3.
ask multi "$(request open "$here/open" true)"
shown
check "with nothing marked the button reads Open ($(buttons))" state_is '[.buttons[] | [.text, .inverted]] == [["Cancel", false], ["Open", true]] and .foot == ""'
for n in a.txt b.txt c.txt; do
  cursor_to "$n"
  wtype -M ctrl -k space -m ctrl
done
until_ok 2000 state_is '.marked | length == 3'
# one.png is empty on purpose, so only a text file's decode counts here.
check "the cursor over text files decodes no picture ($(journalctl --user -u "$DOTS_DEV_UNIT" --no-pager -o cat | grep 'Unsupported image format' | grep -c '\.txt'))" bash -c '! journalctl --user -u "$DOTS_DEV_UNIT" --no-pager -o cat | grep "Unsupported image format" | grep -q "\.txt"'
check "three marked files read 3 selected and Open 3 ($(pk_state | jq -c '[.foot, .marked]') $(buttons))" \
  state_is '.foot == "3 selected" and [.buttons[] | [.text, .inverted]] == [["Cancel", false], ["Open 3", true]] and all(.rows[] | select(.name | endswith(".txt")); .marked)'
cancel multi
until_ok 3000 rest

# 4. The app hanging up over the launcher hands the launcher back with its query.
niri msg action spawn -- dots-call launcher toggle
until_ok 3000 island_is '.surface == "launcher" and .animating == false'
until_ok 2000 launcher_is '.keyboard and .settled'
wtype fo
until_ok 2000 launcher_is '.query == "fo"'
ask gone "$(request open "$here/open")"
shown
check "over the launcher the takeover is picker and the chip reads Launcher ($(island | jq -c '{surface, takeover}') $(pk_state | jq -c .chip))" \
  eval 'island_is ".takeover == \"picker\" and .surface == \"launcher\"" && state_is ".chip == \"Launcher\""'
kill "$pid"
until_ok 3000 island_is '.takeover == null and .animating == false'
check "the app cancelling sets takeover to null and the launcher is back ($(island | jq -c '{surface, takeover}'))" island_is '.takeover == null and .surface == "launcher"'
check "with its query fo ($(launcher | jq -c '{open, query}'))" launcher_is '.open and .query == "fo"'
until_ok 2000 launcher_is '.keyboard and .settled'
wtype -k Escape
until_ok 3000 rest

# 6. Save: a name field and Save; Enter writes the name back.
ask save "$(request save "$here/fresh" false report.pdf)"
shown
check "a save request draws the name field with report.pdf and Save ($(pk_state | jq -c '[.heading, .name, .focus]') $(buttons))" \
  state_is '.saveField and .name == "report.pdf" and .focus == "name" and [.buttons[] | [.text, .inverted]] == [["Cancel", false], ["Save", true]]'
wtype -k Return
until_ok 3000 answered save
check "Enter writes the name back ($(cat "$out/save" 2>/dev/null))" answer_is save "$(chosen "$here/fresh/report.pdf")"
until_ok 3000 rest

ask replace "$(request save "$here/docs" false report.pdf)"
shown
wtype -k Return
until_ok 2000 state_is '.question'
check "saving over report.pdf draws one line with Keep and a red Replace ($(pk_state | jq -c '{line, buttons, danger}'))" \
  state_is '.line == "report.pdf exists" and [.buttons[] | [.text, .inverted]] == [["Keep", false], ["Replace", true]] and (.buttons[1].fill | ascii_downcase) == (.danger | ascii_downcase)'
check "and answers nothing" unanswered replace
click_box picker-keep
check "Keep returns to the field with the name kept ($(pk_state | jq -c '[.question, .focus, .name]'))" until_ok 2000 state_is '.open and (.question | not) and .focus == "name" and .name == "report.pdf"'
check "and answers nothing" unanswered replace
wtype -k Return
until_ok 2000 state_is '.question'
click_box picker-replace
until_ok 3000 answered replace
check "Replace answers the app ($(cat "$out/replace" 2>/dev/null))" answer_is replace "$(chosen "$here/docs/report.pdf")"
until_ok 3000 rest

# 7. A click on the paper is one Esc level: the question first, then the request.
ask paper "$(request save "$here/docs" false report.pdf)"
shown
wtype -k Return
until_ok 2000 state_is '.question'
point click 40 $((oh - 40))
check "with the question up, a click on the paper dismisses only the question ($(pk_state | jq -c '[.open, .question, .name]'))" until_ok 2000 state_is '.open and (.question | not) and .name == "report.pdf"'
check "and answers nothing" unanswered paper
point click 40 $((oh - 40))
until_ok 3000 answered paper
check "a second click cancels the request and the app gets no file ($(cat "$out/paper" 2>/dev/null))" answer_is paper '{"response":1,"paths":[]}'
until_ok 3000 rest

# 8. A folder request lists folders only, with Choose this folder.
ask folder "$(request folder "$here/pick")"
shown
check "a folder request lists folders only, with an inverted Choose this folder ($(pk_state | jq -c '[.rows[].name]') $(buttons))" \
  state_is '[.rows[].name] == ["Codes/", "music/"] and [.buttons[] | [.text, .inverted]] == [["Cancel", false], ["Choose this folder", true]]'
click_box picker-primary
until_ok 3000 answered folder
check "Choose this folder answers the folder shown ($(cat "$out/folder" 2>/dev/null))" answer_is folder "$(chosen "$here/pick")"

# The picker unloads 30 s after its last request, whatever the island shows by then, so the next request opens it cold.
until_ok 3000 rest
check "the picker unloads within 35 s of its close ($(pk_state | jq -c '{loaded, open}'))" until_ok 35000 state_is '.loaded == false'

exit $((fails > 0))
}
