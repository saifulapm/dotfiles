#!/usr/bin/env bash
# Each picker card is a specimen of its own theme: its real paper at half period, its margins, terminal lines and palette.
{
source "$(dirname "$0")/lib.sh"
unset TMUX

themes_state() { timeout 0.5 qs ipc call themes state 2>/dev/null; }
state_is() { themes_state | jq -e "$1" >/dev/null; }
read -r ox oy < <(niri msg -j outputs | jq -r 'first(.[]).logical | "\(.x) \(.y)"')
# A card's preview box, as "x y" in the output's pixels, from the drawn item.
preview_at() { themes_state | jq -r --arg n "$1" --argjson ox "$ox" --argjson oy "$oy" '.cards[] | select(.name == $n) | .preview | "\(.x + $ox | round) \(.y + $oy | round)"'; }
# The PPM of a w x h region at x,y inside card $1's preview.
grab() { local px py; read -r px py < <(preview_at "$1"); grim -s 1 -t ppm -g "$((px + $2)),$((py + $3)) ${4}x${5}" -; }
# How many distinct colours a PPM on stdin holds.
shades() {
  node -e '
    const b = require("fs").readFileSync(0);
    const head = b.toString("latin1").match(/^P6\s+(\d+)\s+(\d+)\s+(\d+)\s/);
    const px = b.subarray(head[0].length), seen = new Set();
    for (let i = 0; i < head[1] * head[2] * 3; i += 3) seen.add((px[i] << 16) | (px[i + 1] << 8) | px[i + 2]);
    console.log(seen.size);
  '
}
# For a one-row PPM on stdin: exits 0 when it holds 8 or more pixels darker ($1 = dark) or brighter (bright) than the row's commonest colour, r+g+b by $2 or more, and every gap between them is a whole number of the pattern's 8 px times the card's fit ($3), within 1 px; a scaled pattern aliases, so a mark lands on whole pixels and a faint one can drop out.
every8() {
  node -e '
    const b = require("fs").readFileSync(0);
    const head = b.toString("latin1").match(/^P6\s+(\d+)\s+(\d+)\s+(\d+)\s/);
    const px = b.subarray(head[0].length), w = Number(head[1]);
    const lum = (x) => px[x * 3] + px[x * 3 + 1] + px[x * 3 + 2];
    const counts = new Map();
    for (let x = 0; x < w; x++) counts.set(lum(x), (counts.get(lum(x)) ?? 0) + 1);
    const base = [...counts].sort((a, z) => z[1] - a[1])[0][0];
    const [dir, thr, fit] = [process.argv[1], Number(process.argv[2]), Number(process.argv[3])];
    const at = [];
    for (let x = 0; x < w; x++) if ((dir === "dark" ? base - lum(x) : lum(x) - base) >= thr) at.push(x);
    const period = 8 * fit, gaps = at.slice(1).map((x, i) => x - at[i]);
    const off = gaps.filter((g) => Math.abs(g - Math.max(1, Math.round(g / period)) * period) > 1);
    console.error(`${at.length} marks at ${at.join(" ")}; gaps off the ${period.toFixed(1)} px period: ${off.join(" ") || "none"}`);
    process.exit(at.length >= 8 && off.length === 0 ? 0 : 1);
  ' "$1" "$2" "$3"
}
has_rgb() {
  node -e '
    const [r, g, b, tol] = process.argv.slice(1).map(Number);
    const buf = require("fs").readFileSync(0);
    const head = buf.toString("latin1").match(/^P6\s+(\d+)\s+(\d+)\s+(\d+)\s/);
    const px = buf.subarray(head[0].length);
    for (let i = 0; i < head[1] * head[2] * 3; i += 3) {
      if (Math.abs(px[i] - r) <= tol && Math.abs(px[i + 1] - g) <= tol && Math.abs(px[i + 2] - b) <= tol) process.exit(0);
    }
    process.exit(1);
  ' "$@"
}
hex_rgb() { printf '%d %d %d' "0x${1:1:2}" "0x${1:3:2}" "0x${1:5:2}"; }
near6() { local a b; read -r -a a <<<"$1"; read -r -a b <<<"$2"; for i in 0 1 2; do ((a[i] - b[i] <= 6 && b[i] - a[i] <= 6)) || return 1; done; }

until_ok 5000 shell_status >/dev/null
until_ok 3000 bash -c "timeout 0.5 qs ipc call shell status | jq -e '.theme == \"paper\"' >/dev/null"
niri msg action spawn -- dots-call themes toggle
until_ok 3000 state_is '.open and .settled and (.cards | length == 5) and all(.cards[]; .paperReady)'
check "the picker shows five cards, each paper settled" state_is '.open and (.cards | length == 5) and all(.cards[]; .paperReady)'
# Below the windows and their shadows, the bottom rows of a preview are bare paper.
# Five cards scale each specimen by the card's fit, so a sample's place inside the 196 px preview scales with it.
fit=$(themes_state | jq '.cards[0].preview.h / 196')
at() { node -e "console.log(Math.round($1 * $fit))"; }
paper_shades() { (($(grab paper "$(at 60)" "$(at 184)" 40 8 | shades) >= 20)); }
check "paper: a 40x8 sample of its card paper holds 20 or more shades ($(grab paper "$(at 60)" "$(at 184)" 40 8 | shades))" paper_shades
artboard_dots() { grab artboard "$(at 20)" "$(at 192)" 120 1 | every8 dark 18 "$fit"; }
check "artboard: its card's bottom row holds a darker dot every 8 px of the specimen, at the card's fit $fit" artboard_dots
dot_colour() { grab artboard "$(at 4)" "$(at 20)" 8 8 | has_rgb 180 186 196 14; }
check "artboard: its card shows a #B4BAC4 dot" dot_colour
# Blueprint's minor lines are cyan at 5 %, about 25 over the cell in r+g+b, the flat fill 0; x 16 on clears the crop mark.
blueprint_grid() { grab blueprint "$(at 20)" "$(at 190)" 120 1 | every8 bright 12 "$fit"; }
check "blueprint: its card's bottom row holds a brighter grid line every 8 px of the specimen, at the card's fit $fit" blueprint_grid

for name in paper artboard blueprint frost hi-fi; do
  card=$(themes_state | jq -c --arg n "$name" '.cards[] | select(.name == $n)')
  want=$(node --input-type=module -e "
    import { readFileSync } from 'node:fs';
    import { parseToml } from '$repo/shell/lib/toml.mjs';
    import { validateTheme, checkTokens } from '$repo/shell/lib/theme.mjs';
    import { swatches } from '$repo/shell/lib/themes.mjs';
    console.log(swatches(checkTokens(validateTheme(parseToml(readFileSync('$repo/themes/$name/theme.toml', 'utf8'))))).join(' '));
  ")
  read -r -a colours <<<"$want"
  swatch_ok=0
  for i in 0 1 2 3 4 5 6 7; do
    read -r sx sy < <(jq -r --argjson i "$i" --argjson ox "$ox" --argjson oy "$oy" '.swatches[$i] | "\(.x + .w / 2 - 2 + $ox | round) \(.y + 3 + $oy | round)"' <<<"$card")
    got=$(grim -s 1 -t ppm -g "$sx,$sy 4x4" - | mean_rgb)
    near6 "$got" "$(hex_rgb "${colours[i]}")" || { echo "     $name swatch $i is $got, not ${colours[i]}"; swatch_ok=1; }
  done
  check "$name: its eight swatches are its palette strip (${colours[*]})" test "$swatch_ok" = 0
  check "$name: its terminal draws four lines" test "$(jq '.terminal | length' <<<"$card")" = 4
done
check "the cards' margins read 03 — FOOT · ~, Page 03 / foot — ~, [03] FOOT — ~, Frost's 3  foot and Hi-Fi's 03  FOOT ($(themes_state | jq -c '[.cards[].left]'))" \
  state_is '[.cards[].left] == ["03 — FOOT · ~", "Page 03 / foot — ~", "[03] FOOT — ~", "3  foot", "03  FOOT"]'
check "hi-fi: its card's bar lights one lamp, the shown workspace's" state_is '.cards[4].lamps == ["lit"]'

wtype -k Escape
exit $((fails > 0))
}
