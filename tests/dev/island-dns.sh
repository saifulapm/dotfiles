#!/usr/bin/env bash
# DNS Shield in the island as board 8 draws it: 880 px in two panes, the rows in the island's ink on its fill, and Kid mode turned on gives a row an inverted Kid chip.
{
source "$(dirname "$0")/lib.sh"

# The shell runs whatever DOTS_DNS names, so the check ends before any open unless that is the fake.
unit_env=$(systemctl --user show -p Environment --value "$DOTS_DEV_UNIT" | tr ' ' '\n')
if ! grep -qxF "DOTS_DNS=$repo/bin/dev-fake-dns" <<<"$unit_env"; then
  echo "FAIL the shell unit's DOTS_DNS is the fake"
  exit 1
fi

log=$DOTS_DEV_DIR/dns.log
dns_state() { timeout 0.5 dots-call dns state 2>/dev/null; }
state_is() { dns_state | jq -e "$@" >/dev/null 2>&1; }
island() { timeout 0.5 qs ipc call island state 2>/dev/null; }
island_is() { island | jq -e "$@" >/dev/null 2>&1; }
logged_is() { [ -e "$log" ] && [ "$(grep -cxF -- "$1" "$log")" = "$2" ]; }
idle() { until_ok 3000 state_is '.busy == false and (.rows | length) > 0'; }
# Pixels of geometry $1 within 40 of the hex colour $2 on every channel, so text drawn in that colour shows as a count.
near_colour() {
  grim -s 1 -t ppm -g "$1" - | node -e '
    const b = require("fs").readFileSync(0), hex = process.argv[1];
    const [r, g, bl] = [1, 3, 5].map((i) => parseInt(hex.slice(i, i + 2), 16));
    const head = b.toString("latin1").match(/^P6\s+(\d+)\s+(\d+)\s+(\d+)\s/), px = b.subarray(head[0].length);
    let n = 0;
    for (let i = 0; i < head[1] * head[2]; i++) if (Math.abs(px[i * 3] - r) <= 40 && Math.abs(px[i * 3 + 1] - g) <= 40 && Math.abs(px[i * 3 + 2] - bl) <= 40) n++;
    console.log(n);
  ' "$2"
}
geo() { jq -r '"\(.x | floor),\(.y | floor) \(.w | ceil)x\(.h | ceil)"'; }
# The island's ink and fill on the scheme the nested shell runs, in QML's lower-case hex, and the scheme's own ink the old card drew in.
island_colours() {
  node --input-type=module -e '
    const [repo, name] = process.argv.slice(1);
    const { schemeTokens } = await import(repo + "/shell/lib/colorscheme-file.mjs");
    const { surfaceStyle } = await import(repo + "/shell/lib/surface.mjs");
    const t = schemeTokens(name), s = surfaceStyle(t, "island");
    console.log(JSON.stringify({ on: s.text.toLowerCase(), fill: s.fill.toLowerCase(), paperInk: t.color.ink.toLowerCase() }));
  ' "$repo" "$(shell_status | jq -r .theme)"
}
colours=$(island_colours)
on=$(jq -r .on <<<"$colours")
fill=$(jq -r .fill <<<"$colours")
paper_ink=$(jq -r .paperInk <<<"$colours")
wife=carried:dev00wife

read -r _ oh < <(niri msg -j outputs | jq -r '.[] | .logical | "\(.width) \(.height)"')
niri msg action spawn -- dots-call dns toggle
until_ok 3000 island_is '.surface == "dns" and .animating == false'
until_ok 3000 state_is '.keyboard and .settled'
idle
echo "     island: $(island | jq -c '{surface, width, height}'), card: $(dns_state | jq -c '{cardBox, listWidth, tileBox}')"
check "Mod+Shift+D sets surface to dns and the island 880 px wide" island_is '.surface == "dns" and .width == 880'
check "the island is no taller than the output less 48 ($oh)" island_is --argjson h "$oh" '.height <= $h - 48'
check "the list is 340 px and the tile ends 16 px inside the island's right edge" state_is '.listWidth == 340 and ((.cardBox.x + .cardBox.w) - (.tileBox.x + .tileBox.w) - 16 | fabs) < 1'
check "the header has the shield, DNS Shield and Add device ($(dns_state | jq -c '[.heading, .addButton]'))" state_is '.heading == "DNS Shield" and .addButton == "Add device"'

# The rows draw on the island's fill in its ink, not in the scheme's own ink the old card drew on paper.
name_geo=$(dns_state | jq '.rows[] | select(.key == "carried:dev00wife") | .nameBox' | geo)
ink_px=$(near_colour "$name_geo" "$on")
check "Wife's iPhone's name $name_geo draws $ink_px px in the island's ink $on, not the paper ink $paper_ink" test "$ink_px" -ge 20

# Kid mode on gives the row an inverted chip: filled with the island's ink, its word in the island's fill.
wtype jj
until_ok 1000 state_is --arg k "$wife" '.cursor == $k'
check "Wife's iPhone starts with no chip and Kid mode off" state_is --arg k "$wife" 'any(.rows[]; .key == $k and .badge == "") and .pane.kid == false'
wtype -k space
check "space on Wife's iPhone sends kid $wife on" until_ok 3000 logged_is "kid $wife on" 1
check "and its row gains a Kid chip ($(dns_state | jq -c --arg k "$wife" '.rows[] | select(.key == $k) | [.badge, .chipFill, .chipInk]'))" until_ok 3000 state_is --arg k "$wife" 'any(.rows[]; .key == $k and .badge == "Kid")'
check "inverted: filled $on, its word in $fill" state_is --arg k "$wife" --arg on "$on" --arg fill "$fill" 'any(.rows[]; .key == $k and .chipFill == $on and .chipInk == $fill)'
check "and the tile's Kid mode switch is on" state_is '.pane.kid'
idle
wtype -k space
until_ok 3000 state_is --arg k "$wife" 'any(.rows[]; .key == $k and .badge == "")'

wtype -k Escape
until_ok 3000 state_is '.drawing == false'

exit $((fails > 0))
}
