#!/usr/bin/env bash
# PaperFill at period 0.5 draws Artboard's dots every 8 px, Blueprint's major lines every 40 and its crop marks 7 px long, 4 px in.
{
repo=$(cd "$(dirname "$0")/../.." && pwd)
# The nested shell runs a copy whose Sheet draws at half period, so the edit never reaches the shell/ the live shell watches.
copy=$(mktemp -d)
cp -a "$repo/shell" "$copy/shell"
# The shell runs ../bin helpers from its own dir.
ln -s "$repo/bin" "$copy/bin"
sed -i 's/^\( *\)PaperFill {$/&\n\1    period: 0.5/' "$copy/shell/Paper.qml"
export DOTS_DEV_SHELL=$copy/shell
source "$(dirname "$0")/lib.sh"
cleanup() { rm -rf "$copy"; }

check "the copy's Sheet sets period 0.5" grep -q '^ *period: 0.5$' "$copy/shell/Paper.qml"

paper_layer() { niri msg -j layers | jq -e 'any(.[]; .namespace == "dots-paper" and .layer == "Background")' >/dev/null; }
until_ok 5000 paper_layer
until_ok 5000 shell_status >/dev/null

read -r ox oy w h < <(niri msg -j outputs | jq -r 'first(.[]).logical | "\(.x) \(.y) \(.width) \(.height)"')
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
switch() {
  node "$repo/shell/lib/theme-render.mjs" "$1" >/dev/null
  printf '%s\n' "$1" >"$XDG_STATE_HOME/dots/theme"
}

# A point 8 px past a multiple of 16 is mid-cell at the full period and a dot at half.
dx=$((ox + w / 2 / 16 * 16 + 8)) dy=$((oy + h / 2 / 16 * 16 + 8))
switch artboard
artboard_up() { near6 "$(mean_at "$((dx + 3))" "$((dy + 3))" 2 2)" "228 230 234"; }
until_ok 3000 artboard_up
sleep 0.3
dot_shown() { grim -s 1 -t ppm -g "$((dx - 2)),$((dy - 2)) 4x4" - | has_rgb 180 186 196 12; }
check "artboard: a dot #B4BAC4 sits at $dx,$dy" dot_shown
bare() { ! grim -s 1 -t ppm -g "$((dx + 2)),$((dy + 2)) 4x4" - | has_rgb 180 186 196 12; }
check "artboard: 4 px past it is bare paper" bare

# x 40 past a multiple of 80 is between lines at the full period and a major line at half; y 3 past one is off every line.
gx=$((ox + w / 2 / 80 * 80 + 40)) gy=$((oy + h / 2 / 80 * 80 + 3))
switch blueprint
blueprint_up() { near6 "$(mean_at "$((gx + 4))" "$gy" 1 1)" "12 26 46"; }
until_ok 3000 blueprint_up
sleep 0.3
read -r lr lg lb < <(mean_at "$gx" "$gy" 1 1)
read -r cr cg cb < <(mean_at "$((gx + 4))" "$gy" 1 1)
check "blueprint: the major line at x $gx ($lr $lg $lb) is brighter than the cell ($cr $cg $cb)" \
  test $((lr + lg + lb - cr - cg - cb)) -ge 30
mark_in() { grim -s 1 -t ppm -g "$((ox + 4)),$((oy + 4)) 3x3" - | has_rgb 127 227 240 12; }
check "blueprint: the crop mark #7FE3F0 starts 4 px in" mark_in
mark_short() { ! grim -s 1 -t ppm -g "$((ox + 11)),$((oy + 4)) 12x12" - | has_rgb 127 227 240 12; }
check "blueprint: the crop mark ends 7 px long" mark_short

exit $((fails > 0))
}
