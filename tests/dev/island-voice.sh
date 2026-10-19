#!/usr/bin/env bash
# The island's notification speaks in each theme's voice: Blueprint's [ APP ] and T+0S over a cyan summary, Paper's serif, Artboard's tile.
{
source "$(dirname "$0")/lib.sh"

island() { timeout 0.5 qs ipc call island state 2>/dev/null; }
state_is() { island | jq -e "$1" >/dev/null 2>&1; }
status_theme() { shell_status | jq -e --arg t "$1" '.theme == $t' >/dev/null; }
in_theme() { "$repo/bin/dots" theme "$1" >/dev/null; until_ok 2000 status_theme "$1"; }
# A notification the shell shows once its morph has settled, so its boxes are where they stay.
shown() { until_ok 3000 state_is "$1 and .mode == \"notification\" and .animating == false"; }
# Pixels of geometry $1 within $5 of r g b.
near() {
  grim -s 1 -t ppm -g "$1" - | node -e '
    const b = require("fs").readFileSync(0), [r, g, bl, tol] = process.argv.slice(1).map(Number);
    const head = b.toString("latin1").match(/^P6\s+(\d+)\s+(\d+)\s+(\d+)\s/), px = b.subarray(head[0].length);
    let n = 0;
    for (let i = 0; i < head[1] * head[2]; i++) if (Math.abs(px[i * 3] - r) <= tol && Math.abs(px[i * 3 + 1] - g) <= tol && Math.abs(px[i * 3 + 2] - bl) <= tol) n++;
    console.log(n);
  ' "$2" "$3" "$4" "$5"
}
geo() { island | jq -r ".note.$1 | \"\(.x | floor),\(.y | floor) \(.w | floor)x\(.h | floor)\""; }
# Notify with an app name notify-send would not send as given; the newest notification replaces the shown one, so each check waits for its own summary.
notify_as() { gdbus call --session --dest org.freedesktop.Notifications --object-path /org/freedesktop/Notifications --method org.freedesktop.Notifications.Notify "$1" 0 "" "$2" "" '[]' '{}' 5000 >/dev/null; }

until_ok 5000 shell_status >/dev/null

in_theme blueprint
notify-send "Download complete" "report-october.pdf · 2.4 MB"
shown '.note.summary == "DOWNLOAD COMPLETE"'
echo "     note: $(island | jq -c .note)"
check "blueprint: the island reads [ NOTIFY-SEND ] and T+0S over DOWNLOAD COMPLETE" state_is '.note.app == "[ NOTIFY-SEND ]" and .note.age == "T+0S"'
# While a notification shows, the clock's minute tick and its 5 s hold are the only timers: nothing counts T+0S up.
check "blueprint: while the notification shows, status reports two timers, the clock and the hold" eval 'shell_status | jq -e ".timers == 2" >/dev/null'
cyan=$(near "$(geo summaryBox)" 127 227 240 10)
check "blueprint: the summary's pixels read #7FE3F0 ($cyan px)" test "$cyan" -gt 150

notify_as "" "no app"
shown '.note.summary == "NO APP"'
check "blueprint: an empty app name draws no empty brackets" state_is '.note.app == "" and .note.bracketsShown == false'

long="App $(printf 'long%.0s' {1..60})"
notify_as "$long" "long app"
shown '.note.summary == "LONG APP"'
echo "     note: $(island | jq -c .note)"
check "blueprint: a long app name elides inside its brackets, short of T+0S" state_is '.note.appElided and .note.bracketsShown and .note.bracketEnd < .note.ageStart'

in_theme paper
notify-send "Download complete" "report-october.pdf · 2.4 MB"
shown '.note.summary == "Download complete"'
check "paper: the island reads NOTIFY-SEND and NOW in caps" state_is '.note.app == "NOTIFY-SEND" and .note.age == "NOW"'
check "paper: the summary draws in Instrument Serif at 24 px ($(island | jq -c .note.summaryFont))" state_is '.note.summaryFont == ["Instrument Serif", 24]'

notify_as "" "no app"
shown '.note.summary == "no app"'
check "paper: an empty app name draws no empty caps" state_is '.note.app == ""'

in_theme artboard
notify-send "Download complete" "report-october.pdf · 2.4 MB"
shown '.note.summary == "Download complete"'
echo "     note: $(island | jq -c .note)"
check "artboard: the island reads the app and now, muted" state_is '.note.app == "notify-send" and .note.age == "now"'
check "artboard: the notification shows a 40 px tile with its glyph" state_is '.note.tileBox.w == 40 and .note.tileBox.h == 40 and .note.glyph == "N"'
tile=$(near "$(geo tileBox)" 43 47 54 4)
check "artboard: the tile at the notification's left reads #2B2F36 ($tile of 1600 px)" test "$tile" -gt 1000
check "artboard: the tile sits at the card's left" state_is '.note.tileBox != null and .note.tileBox.x < .note.summaryBox.x'
# Each notification above replaced the one before; the last one's 5 s end before the timers are counted.
until_ok 6000 state_is '.mode == "rest"'
status=$(shell_status)
check "status still reports one running timer: T+0S is the age at arrival" eval 'jq -e ".timers == 1" <<<"$status" >/dev/null'

exit $((fails > 0))
}
