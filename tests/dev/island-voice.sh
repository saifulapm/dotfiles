#!/usr/bin/env bash
# The island's notification speaks in each theme's voice: Blueprint's [ APP ] and T+0S over a cyan summary, Paper's serif, Artboard's tile.
{
source "$(dirname "$0")/lib.sh"

island() { timeout 0.5 qs ipc call island state 2>/dev/null; }
state_is() { island | jq -e "$1" >/dev/null 2>&1; }
status_theme() { shell_status | jq -e --arg t "$1" '.theme == $t' >/dev/null; }
in_theme() { legacy_theme "$1" >/dev/null; until_ok 2000 status_theme "$1"; }
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
# The WCAG contrast of the text drawn in geometry $1 against the fill behind it: the fill is the box's commonest colour, the text its tenth most distant pixel.
drawn_contrast() {
  grim -s 1 -t ppm -g "$1" - | node -e '
    const b = require("fs").readFileSync(0);
    const head = b.toString("latin1").match(/^P6\s+(\d+)\s+(\d+)\s+(\d+)\s/), px = b.subarray(head[0].length), n = head[1] * head[2];
    const lum = (i) => [0, 1, 2].map((c) => px[i * 3 + c] / 255).map((v) => (v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4)).reduce((s, v, c) => s + v * [0.2126, 0.7152, 0.0722][c], 0);
    const counts = new Map();
    for (let i = 0; i < n; i++) { const k = px.readUIntBE(i * 3, 3); counts.set(k, (counts.get(k) ?? 0) + 1); }
    const fillKey = [...counts].sort((a, z) => z[1] - a[1])[0][0];
    let fillAt = 0;
    while (px.readUIntBE(fillAt * 3, 3) !== fillKey) fillAt++;
    const f = lum(fillAt), ratios = [];
    for (let i = 0; i < n; i++) { const l = lum(i); ratios.push((Math.max(l, f) + 0.05) / (Math.min(l, f) + 0.05)); }
    ratios.sort((a, z) => z - a);
    console.log((ratios[9] ?? 1).toFixed(2), "#" + fillKey.toString(16).padStart(6, "0"));
  '
}
# Notify with an app name notify-send would not send as given; the newest notification replaces the shown one, so each check waits for its own summary.
notify_as() { gdbus call --session --dest org.freedesktop.Notifications --object-path /org/freedesktop/Notifications --method org.freedesktop.Notifications.Notify "$1" 0 "" "$2" "${3:-}" '[]' '{}' 5000 >/dev/null; }

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

# Any app can send a newline or a bidi override; the island keeps app and summary to one line each and draws the body in its spelt order.
notify_as $'two\nlines' $'Download\ncomplete' $'x\u202Eyz'
shown '.note.summary == "DOWNLOAD COMPLETE"'
echo "     note: $(island | jq -c '.note | {app, summaryLines, body, cardBottom, boxBottom}')"
check "blueprint: a newline in the app or summary stays on one line each" state_is '.note.app == "[ TWO LINES ]" and .note.summaryLines == 1'
check "blueprint: the body draws in its spelt order and inside the island" state_is '.note.body == "xyz" and .note.cardBottom <= .note.boxBottom'

in_theme hi-fi
notify-send -a Chromium "Download complete" "report-october.pdf · 2.4 MB"
shown '.note.summary == "DOWNLOAD COMPLETE"'
echo "     note: $(island | jq -c .note)"
check "hi-fi: the island reads CHROMIUM and NOW over DOWNLOAD COMPLETE, with no brackets drawn" state_is '.note.app == "CHROMIUM" and .note.age == "NOW" and .note.bracketsShown == false'
check "hi-fi: nothing the island reports holds a bracket ($(island | marked | head -3 | paste -sd'|'))" eval '[ -z "$(island | marked)" ]'
# The text must read on what is drawn behind it: amber summary on the dark glass #141617, not on an ink slab.
glass=$(near "$(geo summaryBox)" 20 22 23 6)
amber=$(near "$(geo summaryBox)" 250 189 47 12)
cream=$(near "$(geo summaryBox)" 235 219 178 10)
check "hi-fi: the summary is amber #FABD2F ($amber px) on dark glass #141617 ($glass px), with no cream fill ($cream px)" test "$amber" -gt 100 -a "$glass" -gt 200 -a "$cream" -lt 20
# Ink at 6 % over the glass blends to about #212220 in the row under the top border.
lit=$(near "$(geo highlightBox)" 33 34 32 4)
dark=$(near "$(geo highlightBox)" 20 22 23 3)
check "hi-fi: the row under the top border is the highlight ($lit px), not bare glass ($dark px)" test "$lit" -gt 300 -a "$dark" -lt 20
check "hi-fi: the tuning scale is drawn along the bottom edge ($(island | jq -c .note.scale))" state_is '.note.scale.ticks > 40 and .note.scale.box.y + .note.scale.box.h <= .note.boxBottom'
# The ticks are amber at 50 % and 28 % over the glass, and the pointer is red #FB4934.
ticks=$(( $(near "$(geo scale.box)" 135 106 35 12) + $(near "$(geo scale.box)" 84 69 30 12) ))
red=$(near "$(geo scale.box)" 251 73 52 8)
check "hi-fi: the scale reads amber ticks ($ticks px) and a red pointer ($red px)" test "$ticks" -gt 100 -a "$red" -gt 12

notify_as Chromium "$(printf 'Tuned %.0s' {1..34})end"
shown '(.note.summary | startswith("TUNED TUNED"))'
echo "     note: $(island | jq -c '.note | {summaryBox, scale, islandBox, boxBottom}')"
check "hi-fi: a 200-character summary stays inside the island, above the scale" state_is '.note.summaryBox.y + .note.summaryBox.h <= .note.scale.box.y and .note.summaryBox.x + .note.summaryBox.w <= .note.islandBox.x + .note.islandBox.w and .note.scale.box.y + .note.scale.box.h <= .note.boxBottom'
ticks=$(( $(near "$(geo scale.box)" 135 106 35 12) + $(near "$(geo scale.box)" 84 69 30 12) ))
red=$(near "$(geo scale.box)" 251 73 52 8)
check "hi-fi: under a long summary the scale still reads its ticks ($ticks px) and red pointer ($red px)" test "$ticks" -gt 100 -a "$red" -gt 12

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
# notify-send -i sends a path as the image-path hint, not as the app icon.
notify-send -i /usr/share/icons/hicolor/48x48/apps/foot.png "With icon"
shown '.note.summary == "With icon"'
check "artboard: an icon sent as a path draws in the tile instead of the letter" state_is '.note.tileBox != null and .note.glyph == null'
check "artboard: the tile sits at the card's left" state_is '.note.tileBox != null and .note.tileBox.x < .note.summaryBox.x'
# Frost is a dark plain theme: its island is glass, not its light ink, so Artboard's layout reads on it.
in_theme frost
notify-send -a Chromium "Download complete" "report-october.pdf · 2.4 MB"
shown '.note.summary == "Download complete"'
echo "     note: $(island | jq -c '.note | {app, age, summaryColor, tileBox, glyph, bodyBox}')"
check "frost: the card reads Chromium and now over a #eceff4 title" state_is '.note.app == "Chromium" and .note.age == "now" and .note.summaryColor == "#eceff4"'
check "frost: the notification shows a 32 px tile" state_is '.note.tileBox.w == 32 and .note.tileBox.h == 32'
read -r ratio fill < <(drawn_contrast "$(geo bodyBox)")
check "frost: the muted body reads at 4.5:1 or more against the glass drawn behind it ($ratio on $fill)" node -e 'process.exit(+process.argv[1] >= 4.5 ? 0 : 1)' "$ratio"
read -r ratio fill < <(drawn_contrast "$(geo summaryBox)")
check "frost: the summary reads at 4.5:1 or more against the island drawn behind it ($ratio on $fill)" node -e 'process.exit(+process.argv[1] >= 4.5 ? 0 : 1)' "$ratio"
# Frost's glass is #3B4252 at 85 % over the #2E3440 paper, #394050 where nothing shows through.
glass_fill() { local f=$((16#${fill#\#})) w=$((16#394050)) i; for i in 16 8 0; do (((f >> i & 255) - (w >> i & 255) <= 8 && (w >> i & 255) - (f >> i & 255) <= 8)) || return 1; done; }
check "frost: that fill is Frost's glass over its paper, near #394050, not its light ink ($fill)" glass_fill
# Each notification above replaced the one before; the last one's 5 s end before the timers are counted.
until_ok 6000 state_is '.mode == "rest"'
status=$(shell_status)
check "status still reports one running timer: T+0S is the age at arrival" eval 'jq -e ".timers == 1" <<<"$status" >/dev/null'

exit $((fails > 0))
}
