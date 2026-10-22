#!/usr/bin/env bash
# Keys that come before a folder's listing lands, and folders whose names the listing has to survive: no row of a folder other than the one shown is drawn or answered.
{
source "$(dirname "$0")/lib.sh"

sock=$XDG_RUNTIME_DIR/dots-picker-$WAYLAND_DISPLAY.sock
base=$DOTS_DEV_DIR/race out=$DOTS_DEV_DIR/answers
odd=$base/odd link=$base/link save=$base/save dl=$base/dl first=$base/first big=$base/big pick=$base/pick
mkdir -p "$odd" "$link" "$save/drafts" "$dl/screenshots" "$first" "$big" "$pick/sub" "$out"
: >"$odd/ok.txt"
: >"$odd/report.pdf"
# Latin-1 é, which is not UTF-8, as a name copied off an old disk has it.
python3 -c "import sys; open(sys.argv[1].encode() + b'/caf\xe9.txt', 'w').close()" "$odd"
ln -sfn /nonexistent "$link/report.pdf"
: >"$save/notes.md"
: >"$save/drafts/report.pdf"
touch "$dl/screenshots/one.png" "$dl/screenshots/two.png" "$dl/screenshots/three.png" "$dl/other.pdf"
touch "$first/first-a.txt" "$first/first-b.txt" "$first/first-c.txt"
# Enough folders, each counted, that the second listing takes longer than a state read.
mkdir -p "$big"/d{00001..20000}
# sub/ lists inside.txt and inside2.txt first, and enough files after them that its listing outlasts a burst of keys.
touch "$pick/sub/inside.txt" "$pick/sub/inside2.txt" "$pick/sub"/z{00001..20000}

pk_state() { timeout 0.5 dots-call picker state 2>/dev/null; }
state_is() { pk_state | jq -e "$@" >/dev/null 2>&1; }
request() { jq -cn --arg mode "$1" --arg folder "$2" '{mode: $mode, multiple: false, title: "Race", app: "kak", folder: $folder, name: "report.pdf", filters: [], filter: 0, accept: ""}'; }
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
unanswered() { ! until_ok 600 answered "$1"; }
shown() { until_ok 4000 state_is '.open and .settled and .listed'; }
cancel() { wtype -k Escape; until_ok 3000 answered "$1"; }
cursor_to() {
  local i
  for i in 1 2 3 4 5 6; do
    until_ok 300 state_is --arg n "$1" '.rows[.selected].name == $n' && return 0
    wtype -k Down
  done
  return 1
}

for i in 1 2 3 4 5; do
  ask "odd-$i" "$(request save "$odd")"
  shown
  check "run $i: a folder with a name that is not UTF-8 lists the rest ($(pk_state | jq -c '[.rows[].name]'))" state_is '[.rows[].name] == ["caf�.txt", "ok.txt", "report.pdf"]'
  wtype -k Return
  check "run $i: and a save of report.pdf there asks ($(pk_state | jq -c '[.folder, .question, .hint]'))" until_ok 2000 state_is '.question'
  check "run $i: and does not answer" unanswered "odd-$i"
  wtype -k Escape
  until_ok 2000 state_is '.question | not'
  cancel "odd-$i"
done

ask undecodable "$(request open "$odd")"
shown
cursor_to "caf"$'�'".txt"
wtype -k Return
check "Enter on the name that is not UTF-8 answers nothing, as its path names no file ($(cat "$out/undecodable" 2>/dev/null))" unanswered undecodable
cancel undecodable

for i in 1 2 3 4 5; do
  ask "link-$i" "$(request save "$link")"
  shown
  wtype -k Return
  check "run $i: a save over a dangling link named report.pdf asks ($(pk_state | jq -c '[.rows[].name, .question]'))" until_ok 2000 state_is '.question'
  check "run $i: and does not answer" unanswered "link-$i"
  wtype -k Escape
  until_ok 2000 state_is '.question | not'
  cancel "link-$i"
done

for i in 1 2 3 4 5; do
  ask "drafts-$i" "$(request save "$save")"
  shown
  wtype -k Down
  until_ok 2000 state_is '.rows[.selected].name == "drafts/"'
  wtype -k Return -k Return
  check "run $i: Enter Enter on drafts/ asks about drafts/report.pdf ($(until_ok 2000 state_is '.question'; pk_state | jq -c '[.folder, .question, .notice]'))" state_is --arg f "$save/drafts" '.folder == $f and .question'
  check "run $i: and does not answer ($(cat "$out/drafts-$i" 2>/dev/null))" unanswered "drafts-$i"
  wtype -k Escape
  until_ok 2000 state_is '.question | not'
  cancel "drafts-$i"
done

for i in 1 2 3 4 5; do
  ask "typed-$i" "$(request save "$big/d00001")"
  shown
  # big's 20000 folders list slower than a stall between the keys; the Enter, kept, would enter d00001 again.
  wtype -k Left -k Return z
  check "run $i: a letter typed after a waiting Enter drops it ($(until_ok 2000 state_is '.listed'; pk_state | jq -c '[.folder, .name, .question]'))" state_is --arg f "$big" '.open and .folder == $f and .name == "report.pdfz" and (.question | not)'
  check "run $i: and answers nothing ($(cat "$out/typed-$i" 2>/dev/null))" unanswered "typed-$i"
  cancel "typed-$i"
done

for i in 1 2 3 4 5; do
  ask "left-$i" "$(request open "$dl/screenshots")"
  shown
  wtype -k Left -k Return
  # Enter waits for the parent's rows, where the cursor sits on the folder just left, and enters it again.
  check "run $i: Left Enter acts on the parent's rows, not screenshots' ($(until_ok 2000 state_is '.listed and .folder == "'"$dl/screenshots"'"'; pk_state | jq -c '[.open, .folder]') $(cat "$out/left-$i" 2>/dev/null))" state_is --arg f "$dl/screenshots" '.open and .listed and .folder == $f'
  check "run $i: and answers nothing" unanswered "left-$i"
  cancel "left-$i"
done

for i in 1 2 3 4 5; do
  ask "down-$i" "$(request open "$pick")"
  shown
  # The Down comes while sub/ is still listing; it moves the cursor once the rows land, and the held Enter acts on the row it reached.
  wtype -k Return -k Down -k Return
  check "run $i: Enter Down Enter on sub/ answers inside2.txt ($(until_ok 3000 answered "down-$i"; cat "$out/down-$i" 2>/dev/null))" answer_is "down-$i" '{"response":0,"paths":["'"$pick/sub/inside2.txt"'"]}'
done

for i in 1 2 3 4 5; do
  ask "updown-$i" "$(request open "$pick")"
  shown
  wtype -k Return -k Down -k Down -k Up -k Return
  check "run $i: Enter Down Down Up Enter on sub/ answers inside2.txt ($(until_ok 3000 answered "updown-$i"; cat "$out/updown-$i" 2>/dev/null))" answer_is "updown-$i" '{"response":0,"paths":["'"$pick/sub/inside2.txt"'"]}'
done

for i in 1 2 3 4 5; do
  ask "keep-$i" "$(request save "$base")"
  shown
  cursor_to "big/"
  wtype -k Return -k Down
  # big's first row is a folder, so the Down moves onto it and leaves the name as it was.
  check "run $i: save, Enter Down into big/ moves onto d00001/ and keeps the name ($(until_ok 3000 state_is '.listed and .selected >= 0'; pk_state | jq -c '[.folder, .rows[.selected].name, .name]'))" state_is --arg f "$big" '.open and .folder == $f and .rows[.selected].name == "d00001/" and .name == "report.pdf"'
  check "run $i: and answers nothing ($(cat "$out/keep-$i" 2>/dev/null))" unanswered "keep-$i"
  cancel "keep-$i"
done

# The state read that first sees the second card open.
opened() {
  local s i
  for i in $(seq 1 80); do
    s=$(pk_state)
    jq -e .open <<<"$s" >/dev/null 2>&1 && { echo "$s"; return 0; }
    sleep 0.02
  done
  return 1
}
holds() { jq -e "$2" <<<"$1" >/dev/null 2>&1; }
for i in 1 2 3 4 5; do
  ask "first-$i" "$(request open "$first")"
  shown
  cancel "first-$i"
  until_ok 2000 state_is '.open | not'
  ask "second-$i" "$(request open "$big")"
  s=$(opened)
  check "run $i: the second card draws no row of the first folder ($(jq -c '[.folder, .listed, [.rows[].name][0:3]]' <<<"$s"))" holds "$s" '.open and ([.rows[].name] | all(startswith("first-") | not))'
  shown
  cancel "second-$i"
done

exit $((fails > 0))
}
