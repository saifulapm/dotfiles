#!/usr/bin/env bash
# A notification's looks: its app's icon from its desktop entry, its picture, its progress bar, and a stack tag that keeps one of them.
{
source "$(dirname "$0")/lib.sh"

island() { timeout 0.5 qs ipc call island state 2>/dev/null; }
state_is() { island | jq -e "$1" >/dev/null 2>&1; }
status_theme() { shell_status | jq -e --arg t "$1" '.theme == $t and .transition == ""' >/dev/null; }
in_theme() { "$repo/bin/dots" theme "$1" >/dev/null; until_ok 8000 status_theme "$1"; }
# The newest notification replaces the shown one, so each check waits for its own summary, drawn and settled.
shown() { until_ok 3000 state_is "(.note.summary | ascii_downcase) == \"$1\" and .animating == false"; }
note() { island | jq -c ".note.$1"; }
notify() { gdbus call --session --dest org.freedesktop.Notifications --object-path /org/freedesktop/Notifications --method org.freedesktop.Notifications.Notify "$@" >/dev/null; }

until_ok 5000 shell_status >/dev/null
in_theme artboard

notify-send -a x -h string:desktop-entry:foot hi
shown hi
check "the desktop-entry hint draws foot's icon, not an X ($(note icon))" state_is '(.note.icon // "" | test("foot")) and .note.glyph == null'
notify-send -a foot named
shown named
check "an app named foot draws foot's icon by name ($(note icon))" state_is '(.note.icon // "" | test("foot")) and .note.glyph == null'
notify-send -a "Unknown Thing" unknown
shown unknown
check "an unknown app keeps the letter U ($(note glyph))" state_is '.note.glyph == "U" and .note.icon == null'
notify "x" 0 "/usr/share/pixmaps/helix.png" given "" '[]' '{"desktop-entry": <"foot">}' 5000
shown given
check "an app icon given beats the desktop entry ($(note icon))" state_is '(.note.icon // "" | test("helix")) and .note.glyph == null'

# The value hint draws the OSD's bar under the body: 40 lights 8 of 20 in each theme, and a replace moves it.
for t in paper artboard blueprint; do
  in_theme "$t"
  notify-send -a dl -h int:value:40 "Download $t"
  shown "download $t"
  check "$t: value 40 lights 8 of 20 ($(note bar))" state_is '.note.bar == 8'
done
id=$(notify-send -p -a dl -h int:value:20 Moving)
shown moving
check "value 20 lights 4 ($(note bar))" state_is '.note.bar == 4'
notify-send -r "$id" -a dl -h int:value:60 Moving
check "a replace with 60 lights 12 ($(note bar))" until_ok 2000 state_is '.note.bar == 12'
notify-send -a dl plain
shown plain
check "no value draws no bar ($(note bar))" state_is '.note.bar == null'

exit $((fails > 0))
}
