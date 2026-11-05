#!/usr/bin/env bash
# PaperFill at period 0.5 draws the dots every 8 px.
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
# A point 8 px past a multiple of 16 is mid-cell at the full period and a dot at half; a quarter down is clear of the day's passage card.
dx=$((ox + w / 2 / 16 * 16 + 8)) dy=$((oy + h / 4 / 16 * 16 + 8))
artboard_up() { near6 "$(mean_at "$((dx + 3))" "$((dy + 3))" 2 2)" "228 230 234"; }
until_ok 3000 artboard_up
# artboard's dots are its line colour, #D0D7DE.
dot_shown() { grim -s 1 -t ppm -g "$((dx - 2)),$((dy - 2)) 4x4" - | has_rgb 208 215 222 8; }
check "artboard: a dot #D0D7DE sits at $dx,$dy" dot_shown
bare() { ! grim -s 1 -t ppm -g "$((dx + 2)),$((dy + 2)) 4x4" - | has_rgb 208 215 222 8; }
check "artboard: 4 px past it is bare paper" bare

exit $((fails > 0))
}
