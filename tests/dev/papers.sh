#!/usr/bin/env bash
# Each scheme's paper: its colour at a cell's middle, and a dot in its line colour that only the shader draws.
{
source "$(dirname "$0")/lib.sh"

paper_layer() { niri msg -j layers | jq -e 'any(.[]; .namespace == "dots-paper" and .layer == "Background")' >/dev/null; }
until_ok 5000 paper_layer
until_ok 5000 shell_status >/dev/null

read -r ox oy w h < <(niri msg -j outputs | jq -r 'first(.[]).logical | "\(.x) \(.y) \(.width) \(.height)"')
# Dots sit on multiples of 16 from the output's top-left, so 3 px into a cell is bare paper; a quarter down sits under the bar and the island and above the day's passage card, which covers the middle.
cx=$((ox + w / 2 / 16 * 16 + 3)) cy=$((oy + h / 4 / 16 * 16 + 3))

mean_at() { grim -s 1 -t ppm -g "$1,$2 $3x$4" - | mean_rgb; }
# Exits 0 if any pixel of the PPM on stdin is within $4 per channel of $1 $2 $3.
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
near6() { local a b; read -r -a a <<<"$1"; read -r -a b <<<"$2"; for i in 0 1 2; do ((a[i] - b[i] <= 6 && b[i] - a[i] <= 6)) || return 1; done; }
centre_is() { near6 "$(mean_at "$cx" "$cy" 10 10)" "$1"; }

rest_in() { shell_status | jq -e --arg t "$1" '.theme == $t and .transition == ""' >/dev/null; }
hex_rgb() { printf '%d %d %d' "0x${1:1:2}" "0x${1:3:2}" "0x${1:5:2}"; }
toml_colour() { sed -n "s/^$2 = \"\(#[0-9A-Fa-f]*\)\"$/\1/p" "$repo/colorschemes/$1.toml"; }

for name in artboard catppuccin-mocha github-light gruvbox-dark rose-pine-dawn; do
  "$repo/bin/dots" colorscheme "$name" >/dev/null
  until_ok 3000 rest_in "$name"
  rgb=$(hex_rgb "$(toml_colour "$name" paper)")
  until_ok 3000 centre_is "$rgb"
  check "$name: the paper at $cx,$cy is $rgb ($(mean_at "$cx" "$cy" 10 10))" centre_is "$rgb"
  read -r lr lg lb <<<"$(hex_rgb "$(toml_colour "$name" line)")"
  dot_shown() { grim -s 1 -t ppm -g "$((cx - 5)),$((cy - 5)) 4x4" - | has_rgb "$lr" "$lg" "$lb" 12; }
  check "$name: a dot in its line colour ($lr $lg $lb) sits at $((cx - 3)),$((cy - 3))" dot_shown
done

errors=$(journalctl --user -u "$DOTS_DEV_UNIT" --no-pager -o cat | grep -E 'Failed to load|ShaderEffect|QShader|\.qsb')
[ -n "$errors" ] && echo "$errors"
check "the shell's journal has no load or shader error" test -z "$errors"

exit $((fails > 0))
}
