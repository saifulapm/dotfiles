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

# A picture draws as a 48 px thumbnail at the card's right, from a file or from image data, but not when it is the app icon's own file.
pic=$(mktemp --suffix=.png)
cleanup() { rm -f "$pic"; }
ffmpeg -loglevel error -y -f lavfi -i color=c=0xff00ff:s=96x96 -frames:v 1 "$pic"
# Pixels on the whole nested output within 12 of the picture's magenta.
magenta() {
  grim -t ppm - | node -e '
    const b = require("fs").readFileSync(0), head = b.toString("latin1").match(/^P6\s+(\d+)\s+(\d+)\s+(\d+)\s/), px = b.subarray(head[0].length);
    let n = 0;
    for (let i = 0; i < head[1] * head[2]; i++) if (px[i * 3] > 242 && px[i * 3 + 1] < 13 && px[i * 3 + 2] > 242) n++;
    console.log(n);
  '
}
right_thumb='.note.picture.w == 48 and .note.picture.h == 48 and .note.picture.x > .note.summaryBox.x + .note.summaryBox.w'
for t in paper artboard blueprint; do
  in_theme "$t"
  notify-send -a Art -h string:image-path:"$pic" "Cover $t"
  shown "cover $t"
  check "$t: an image-path PNG draws a 48 px thumbnail at the right ($(note picture))" state_is "$right_thumb"
done
notify "Art" 0 "" data "" '[]' '{"image-data": <(2, 2, 8, true, 8, 4, [byte 255, 0, 0, 255, 0, 255, 0, 255, 0, 0, 255, 255, 255, 255, 255, 255])>}' 5000
shown data
check "image data sent by gdbus draws the same ($(note picture))" state_is "$right_thumb"
# Mod+A's rows are text only: with the card gone, the open centre shows none of the picture's pixels.
notify-send -a Art -h string:image-path:"$pic" "Cover row"
shown "cover row"
check "the card's thumbnail is magenta on screen ($(magenta) px)" test "$(magenta)" -gt 1000
until_ok 7000 state_is '.mode == "rest"'
notifs() { timeout 0.5 qs ipc call notifs state 2>/dev/null; }
niri msg action spawn -- dots-call notifs open
until_ok 3000 eval 'notifs | jq -e .open >/dev/null'
sleep 0.5
check "its Mod+A row draws no picture ($(magenta) px)" test "$(magenta)" = 0
niri msg action spawn -- dots-call notifs close
until_ok 2000 eval 'notifs | jq -e ".open == false" >/dev/null'

in_theme artboard
notify "Art" 0 "$pic" same "" '[]' "{\"image-path\": <\"$pic\">}" 5000
shown same
check "a picture that is the app icon's file draws no thumbnail ($(note picture))" state_is '.note.picture == null'
check "and draws as the icon in the tile ($(note icon))" state_is '.note.icon != null'
notify-send -i /usr/share/icons/hicolor/48x48/apps/foot.png -a Art themed
shown themed
check "an icon theme's file in image-path is the icon, not a picture ($(note picture))" state_is '.note.picture == null and .note.icon != null'

# A stack tag keeps one notification per app and tag, on the island and in the history.
held() { notifs | jq --arg s "$1" '[.summaries[] | select(. == $s)] | length'; }
timeout 0.5 qs ipc call notifs clear >/dev/null
for p in 20 60 100; do
  notify-send -a dl -h int:value:$p -h string:x-dunst-stack-tag:dl Download
  until_ok 2000 state_is ".note.bar == $((p / 5))"
done
check "three sends in one stack leave one Download in the history ($(held Download))" test "$(held Download)" = 1
sleep 1
check "and its card stays on the island, full ($(note bar))" state_is '.mode == "notification" and .note.bar == 20'
# The older object's close comes as the newer one takes its key, and must leave the newer one's actions live.
notify-send -a dl -h string:x-dunst-stack-tag:dl -A yes=Yes Download >/dev/null &
sender=$!
check "a stacked send keeps its action chip ($(note actions))" until_ok 2000 state_is '.note.actions | length == 1'
kill "$sender"
wait "$sender" 2>/dev/null
notify-send -a other -h string:x-dunst-stack-tag:dl Download
until_ok 2000 eval '[ "$(held Download)" = 2 ]'
check "the same tag from another app makes a second entry ($(held Download))" test "$(held Download)" = 2
for v in 30 70; do
  notify-send -a vol -h int:value:$v -h string:x-canonical-private-synchronous:volume Volume
  until_ok 2000 state_is ".note.bar == $((v / 5))"
done
check "x-canonical-private-synchronous keeps one too ($(held Volume))" test "$(held Volume)" = 1
# The older one's app hears it closed as expired, reason 1, not as dismissed by the user.
bus=$(mktemp)
gdbus monitor --session --dest org.freedesktop.Notifications >"$bus" &
monitor=$!
cleanup() { kill "$monitor" 2>/dev/null; rm -f "$pic" "$bus"; }
first=$(notify-send -p -a vol -h string:x-canonical-private-synchronous:volume Volume)
notify-send -a vol -h string:x-canonical-private-synchronous:volume Volume
expired() { grep -q "NotificationClosed (uint32 $first, uint32 1)" "$bus"; }
check "the replaced one's app hears it expired" until_ok 2000 expired

exit $((fails > 0))
}
