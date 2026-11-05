#!/usr/bin/env bash
# The picker opens on date, newest first, with folders on top; ctrl+, cycles name, size and back, the cursor staying on its file, and every request opens on date again.
{
export DOTS_PICKER_SORT=
source "$(dirname "$0")/lib.sh"

sock=$XDG_RUNTIME_DIR/dots-picker-$WAYLAND_DISPLAY.sock
dir=$DOTS_DEV_DIR/sort out=$DOTS_DEV_DIR/answers
mkdir -p "$dir/y-dir" "$dir/z-dir" "$out"
printf 'x%.0s' {1..300} >"$dir/a-old.txt"
printf 'x%.0s' {1..10} >"$dir/b-new.txt"
printf 'x%.0s' {1..5000} >"$dir/c-mid.txt"
touch -d 2026-01-01 "$dir/a-old.txt"; touch -d 2026-03-01 "$dir/b-new.txt"; touch -d 2026-02-01 "$dir/c-mid.txt"
touch -d 2026-01-15 "$dir/y-dir"; touch -d 2026-04-01 "$dir/z-dir"

pk_state() { timeout 0.5 dots-call picker state 2>/dev/null; }
state_is() { pk_state | jq -e "$@" >/dev/null 2>&1; }
request() { jq -cn --arg mode "$1" --arg folder "$2" '{mode: $mode, multiple: false, title: "", app: "chromium-browser", folder: $folder, name: "", filters: [], filter: 0, accept: ""}'; }
ask() {
  rm -f "$out/$1"
  node -e '
    const [sock, line, file] = process.argv.slice(1), chunks = [];
    const s = require("net").connect(sock, () => s.write(line + "\n"));
    s.on("data", (d) => chunks.push(d));
    s.on("close", () => require("fs").writeFileSync(file, Buffer.concat(chunks)));
  ' "$sock" "$2" "$out/$1" &
}
answered() { [ -e "$out/$1" ]; }
shown() { until_ok 4000 state_is '.open and .settled and .listed'; }
names() { pk_state | jq -c '[.sort, [.rows[].name], .rows[.selected].name]'; }
sort_key() { wtype -M ctrl , -m ctrl; }

ask first "$(request open "$dir")"
shown
check "a request opens on date, newest first, folders on top ($(names))" \
  state_is '.sort == "modified" and [.rows[].name] == ["z-dir/", "y-dir/", "b-new.txt", "c-mid.txt", "a-old.txt"]'
check "and the strip says so ($(pk_state | jq -c .hint))" state_is '.hint | contains("ctrl+, sort: date")'
wtype -k Down -k Down -k Down
until_ok 1000 state_is '.rows[.selected].name == "c-mid.txt"'
sort_key
until_ok 1000 state_is '.sort == "name"'
check "ctrl+, sorts by name and the cursor stays on c-mid.txt ($(names))" \
  state_is '[.rows[].name] == ["y-dir/", "z-dir/", "a-old.txt", "b-new.txt", "c-mid.txt"] and .rows[.selected].name == "c-mid.txt"'
sort_key
until_ok 1000 state_is '.sort == "size"'
check "a second ctrl+, sorts files by size, largest first ($(names))" \
  state_is '[.rows[].name] == ["y-dir/", "z-dir/", "c-mid.txt", "a-old.txt", "b-new.txt"] and .rows[.selected].name == "c-mid.txt"'
sort_key
until_ok 1000 state_is '.sort == "modified"'
check "a third comes back to date ($(names))" state_is '.sort == "modified" and .rows[2].name == "b-new.txt"'
sort_key
wtype -k Escape
until_ok 3000 answered first

ask again "$(request open "$dir")"
shown
check "the next request opens on date again ($(names))" state_is '.sort == "modified"'
wtype -k Escape
until_ok 3000 answered again

ask folder "$(request folder "$dir")"
shown
sort_key
until_ok 1000 state_is '.sort == "name"'
sort_key
until_ok 1000 state_is '.sort != "name"'
check "a folder request skips size: name, then date ($(names))" state_is '.sort == "modified" and [.rows[].name] == ["z-dir/", "y-dir/"]'
wtype -k Escape
until_ok 3000 answered folder

ask arrow "$(request open "$dir")"
shown
check "the head arrows Modified while the rows sort by date ($(pk_state | jq -c .heads))" state_is '.heads == ["Name", "Size", "Modified ↓"]'
sort_key
until_ok 1000 state_is '.sort == "name"'
check "and Name once they sort by name ($(pk_state | jq -c .heads))" state_is '.heads == ["Name ↑", "Size", "Modified"]'
wtype -k Escape
until_ok 3000 answered arrow

exit $((fails > 0))
}
