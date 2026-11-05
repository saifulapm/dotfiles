#!/usr/bin/env bash
# Each picker card is a specimen of its own colorscheme on the one design: its dot paper at half period, its margins, terminal lines and palette.
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
# For a one-row PPM on stdin: exits 0 when it holds 8 or more runs of pixels darker ($1 = dark) or brighter (bright) than the row's commonest colour, r+g+b by $2 or more, and every gap between them is a whole number of the pattern's 8 px times the card's fit ($3), within 1 px; a scaled pattern aliases, so a mark lands on whole pixels and a faint one can drop out.
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
    // A scaled dot can cover two pixels side by side; each run counts once, at its first pixel.
    let prev = false;
    for (let x = 0; x < w; x++) {
      const on = (dir === "dark" ? base - lum(x) : lum(x) - base) >= thr;
      if (on && !prev) at.push(x);
      prev = on;
    }
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
until_ok 3000 bash -c "timeout 0.5 qs ipc call shell status | jq -e '.theme == \"artboard\"' >/dev/null"
niri msg action spawn -- dots-call themes toggle
until_ok 3000 state_is '.open and .settled and (.cards | length == 5) and all(.cards[]; .paperReady)'
check "the picker shows five cards, each paper settled" state_is '.open and (.cards | length == 5) and all(.cards[]; .paperReady)'
# Below the windows, the bottom rows of a preview are bare paper; five cards scale each specimen by the card's fit, so a sample's place inside the 196 px preview scales with it.
fit=$(themes_state | jq '.cards[0].preview.h / 196')
at() { node -e "console.log(Math.round($1 * $fit))"; }
# Artboard's line dots sit about 20 under its paper in r+g+b, after scaling about 6; the scaled dot rows land on fractional pixels, so the rows around the last one are each tried.
dot_row() {
  local y
  for y in 188 189 190 191 192 193; do grab "$1" "$(at 20)" "$(at "$y")" 120 1 | every8 "$2" 6 "$fit" 2>/dev/null && return 0; done
  return 1
}
check "artboard: its card's bottom row holds a darker dot every 8 px of the specimen, at the card's fit $fit" dot_row artboard dark
check "gruvbox-dark: its card's bottom row holds a brighter dot every 8 px of the specimen, at the card's fit $fit" dot_row gruvbox-dark bright
    return 1
  }
  check "$name: its card's bottom row holds a dot every 8 px of the specimen, at the card's fit $fit" dots "$([ "$name" = artboard ] && echo dark || echo bright)"
done

for name in artboard catppuccin-mocha github-light gruvbox-dark rose-pine-dawn; do
  card=$(themes_state | jq -c --arg n "$name" '.cards[] | select(.name == $n)')
  want=$(node --input-type=module -e "
    import { swatches } from '$repo/shell/lib/themes.mjs';
    import { schemeTokens } from '$repo/shell/lib/colorscheme-file.mjs';
    console.log(swatches(schemeTokens('$name')).join(' '));
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
check "every card's margins read Page 03 / foot — ~ ($(themes_state | jq -c '[.cards[].left] | unique'))" \
  state_is '[.cards[].left] | unique == ["Page 03 / foot — ~"]'

wtype -k Escape
exit $((fails > 0))
}
