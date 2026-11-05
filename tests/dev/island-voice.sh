#!/usr/bin/env bash
# The island's notification: the app and now over the summary beside a 40 px tile, drawn solid in the scheme's island fill with ink that reads on it in every colorscheme.
{
source "$(dirname "$0")/lib.sh"

island() { timeout 0.5 qs ipc call island state 2>/dev/null; }
state_is() { island | jq -e "$1" >/dev/null 2>&1; }
in_scheme() { "$repo/bin/dots" colorscheme "$1" >/dev/null; until_ok 3000 eval "shell_status | jq -e --arg t '$1' '.theme == \$t and .transition == \"\"' >/dev/null"; sleep 0.3; }
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
readable() { node -e 'process.exit(+process.argv[1] >= 4.5 ? 0 : 1)' "$1"; }
# Whether drawn colour $1 is within 3 of each channel of $2, the scheme's island fill.
fill_is() { local f=$((16#${1#\#})) w=$((16#${2#\#})) i; for i in 16 8 0; do (((f >> i & 255) - (w >> i & 255) <= 3 && (w >> i & 255) - (f >> i & 255) <= 3)) || return 1; done; }
# A toast in the current scheme, and its summary's drawn contrast and fill.
toast() {
  notify-send -a Chromium "Download complete" "report-october.pdf · 2.4 MB"
  shown '.note.summary == "Download complete"'
  read -r ratio fill < <(drawn_contrast "$(geo summaryBox)")
}
# Notify with an app name notify-send would not send as given; the newest notification replaces the shown one, so each check waits for its own summary.
notify_as() { gdbus call --session --dest org.freedesktop.Notifications --object-path /org/freedesktop/Notifications --method org.freedesktop.Notifications.Notify "$1" 0 "" "$2" "${3:-}" '[]' '{}' 5000 >/dev/null; }

until_ok 5000 shell_status >/dev/null

notify-send "Download complete" "report-october.pdf · 2.4 MB"
shown '.note.summary == "Download complete"'
echo "     note: $(island | jq -c .note)"
check "the island reads the app and now" state_is '.note.app == "notify-send" and .note.age == "now"'
# While a notification shows, the clock's minute tick and its 5 s hold are the only timers: nothing counts now up.
check "while the notification shows, status reports two timers, the clock and the hold" eval 'shell_status | jq -e ".timers == 2" >/dev/null'
check "the notification shows a 40 px tile with its glyph" state_is '.note.tileBox.w == 40 and .note.tileBox.h == 40 and .note.glyph == "N"'
tile=$(near "$(geo tileBox)" 43 47 54 4)
check "the tile at the notification's left reads #2B2F36 ($tile of 1600 px)" test "$tile" -gt 1000

notify_as "" "no app"
shown '.note.summary == "no app"'
check "an empty app name draws nothing in its place" state_is '.note.app == ""'

long="App $(printf 'long%.0s' {1..60})"
notify_as "$long" "long app"
shown '.note.summary == "long app"'
check "a long app name elides short of now" state_is '.note.appElided and .note.appEnd < .note.ageStart'

# Any app can send a newline or a bidi override; the island keeps app and summary to one line each and draws the body in its spelt order.
notify_as $'two\nlines' $'Download\ncomplete' $'x‮yz'
shown '.note.summary == "Download complete"'
echo "     note: $(island | jq -c '.note | {app, summaryLines, body, cardBottom, boxBottom}')"
check "a newline in the app or summary stays on one line each" state_is '.note.app == "two lines" and .note.summaryLines == 1'
check "the body draws in its spelt order and inside the island" state_is '.note.body == "xyz" and .note.cardBottom <= .note.boxBottom'

# notify-send -i sends a path as the image-path hint, not as the app icon.
notify-send -i /usr/share/icons/hicolor/48x48/apps/foot.png "With icon"
shown '.note.summary == "With icon"'
check "an icon sent as a path draws in the tile instead of the letter" state_is '.note.tileBox != null and .note.glyph == null'
check "the tile sits at the card's left" state_is '.note.tileBox != null and .note.tileBox.x < .note.summaryBox.x'

# Each scheme draws the toast solid in its island fill, with a summary that reads on it.
toast
check "artboard: the summary reads at 4.5:1 or more on the island ($ratio on $fill)" readable "$ratio"
check "artboard: the island is solid #15171B ($fill)" fill_is "$fill" '#15171B'
in_scheme catppuccin-mocha
toast
check "catppuccin-mocha: the summary reads at 4.5:1 or more on the island ($ratio on $fill)" readable "$ratio"
check "catppuccin-mocha: the island is solid #1E1E2E ($fill)" fill_is "$fill" '#1E1E2E'
in_scheme github-light
toast
check "github-light: the summary reads at 4.5:1 or more on the island ($ratio on $fill)" readable "$ratio"
check "github-light: the island is solid #1F2328 ($fill)" fill_is "$fill" '#1F2328'
in_scheme gruvbox-dark
toast
check "gruvbox-dark: the summary reads at 4.5:1 or more on the island ($ratio on $fill)" readable "$ratio"
check "gruvbox-dark: the island is solid #282828 ($fill)" fill_is "$fill" '#282828'
in_scheme rose-pine-dawn
toast
check "rose-pine-dawn: the summary reads at 4.5:1 or more on the island ($ratio on $fill)" readable "$ratio"
check "rose-pine-dawn: the island is solid #575279 ($fill)" fill_is "$fill" '#575279'

# Each notification above replaced the one before; the last one's 5 s end before the timers are counted.
until_ok 6000 state_is '.mode == "rest"'
status=$(shell_status)
check "status still reports one running timer: now is the age at arrival" eval 'jq -e ".timers == 1" <<<"$status" >/dev/null'

exit $((fails > 0))
}
