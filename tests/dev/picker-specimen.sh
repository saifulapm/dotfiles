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
# For a one-row PPM on stdin: exits 0 when every 8th pixel from the first is darker ($1 = dark) or brighter (bright) than the pixel 4 along, its r+g+b by $2 or more.
every8() {
  node -e '
    const b = require("fs").readFileSync(0);
    const head = b.toString("latin1").match(/^P6\s+(\d+)\s+(\d+)\s+(\d+)\s/);
    const px = b.subarray(head[0].length), w = Number(head[1]);
    const lum = (x) => px[x * 3] + px[x * 3 + 1] + px[x * 3 + 2];
    let n = 0;
    for (let x = 0; x + 4 < w; x += 8, n++) {
      const d = process.argv[1] === "dark" ? lum(x + 4) - lum(x) : lum(x) - lum(x + 4);
      if (d < Number(process.argv[2])) { console.error(`x ${x}: ${lum(x)} against ${lum(x + 4)}`); process.exit(1); }
    }
    process.exit(n >= 8 ? 0 : 1);
  ' "$1" "$2"
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
niri msg action spawn -- qs ipc call themes toggle
until_ok 3000 state_is '.open and .settled and (.cards | length == 3) and all(.cards[]; .paperReady)'
check "the picker shows three cards, each paper settled" state_is '.open and (.cards | length == 3) and all(.cards[]; .paperReady)'
# Below the windows and their shadows, the bottom rows of a preview are bare paper.
paper_shades() { (($(grab paper 60 186 40 10 | shades) >= 20)); }
check "paper: a 40x10 sample of its card paper holds 20 or more shades ($(grab paper 60 186 40 10 | shades))" paper_shades
artboard_dots() { grab artboard 0 192 81 1 | every8 dark 36; }
check "artboard: every 8th pixel along its card's bottom row is a darker dot" artboard_dots
dot_colour() { grab artboard 4 20 8 8 | has_rgb 180 186 196 14; }
check "artboard: its card shows a #B4BAC4 dot" dot_colour
# Blueprint's minor lines are cyan at 5 %, about 25 over the cell in r+g+b, the flat fill 0; x 16 on clears the crop mark.
blueprint_grid() { grab blueprint 16 190 81 1 | every8 bright 12; }
check "blueprint: every 8th pixel along its card's bottom row is a brighter grid line" blueprint_grid

for name in paper artboard blueprint; do
  card=$(themes_state | jq -c --arg n "$name" '.cards[] | select(.name == $n)')
  want=$(node --input-type=module -e "
    import { readFileSync } from 'node:fs';
    import { parseToml } from '$repo/shell/lib/toml.mjs';
    import { validateTheme } from '$repo/shell/lib/theme.mjs';
    import { swatches } from '$repo/shell/lib/themes.mjs';
    console.log(swatches(validateTheme(parseToml(readFileSync('$repo/themes/$name/theme.toml', 'utf8')))).join(' '));
  ")
  read -r -a colours <<<"$want"
  swatch_ok=0
  for i in 0 1 2 3 4 5 6 7; do
    read -r sx sy < <(jq -r --argjson i "$i" --argjson ox "$ox" --argjson oy "$oy" '.swatches[$i] | "\(.x + .w / 2 - 2 + $ox | round) \(.y + 3 + $oy | round)"' <<<"$card")
    got=$(grim -s 1 -t ppm -g "$sx,$sy 4x4" - | mean_rgb)
    near6 "$got" "$(hex_rgb "${colours[i]}")" || { echo "     $name swatch $i is $got, not ${colours[i]}"; swatch_ok=1; }
  done
  check "$name: its eight swatches are ink, ANSI 1 to 6 and the paper" test "$swatch_ok" = 0
  check "$name: its terminal draws four lines" test "$(jq '.terminal | length' <<<"$card")" = 4
done
check "the cards' margins read 03 — FOOT · ~, Page 03 / foot — ~ and [03] FOOT — ~" \
  state_is '[.cards[].left] == ["03 — FOOT · ~", "Page 03 / foot — ~", "[03] FOOT — ~"]'

wtype -k Escape
exit $((fails > 0))
}
