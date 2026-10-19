#!/usr/bin/env bash
# Each theme's paper: its colour at a cell's middle, Blueprint's crop mark, and a dot and a grid line only the shader draws.
{
source "$(dirname "$0")/lib.sh"

paper_layer() { niri msg -j layers | jq -e 'any(.[]; .namespace == "dots-paper" and .layer == "Background")' >/dev/null; }
until_ok 5000 paper_layer
until_ok 5000 shell_status >/dev/null

read -r ox oy w h < <(niri msg -j outputs | jq -r 'first(.[]).logical | "\(.x) \(.y) \(.width) \(.height)"')
# Dots and grid lines sit on multiples of 16 from the output's top-left, so 3 px into a cell is bare paper.
cx=$((ox + w / 2 / 16 * 16 + 3)) cy=$((oy + h / 2 / 16 * 16 + 3))

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

switch() {
  node "$repo/shell/lib/theme-render.mjs" "$1" >/dev/null
  printf '%s\n' "$1" >"$XDG_STATE_HOME/dots/theme"
}

for t in "paper 241 233 216" "artboard 228 230 234" "blueprint 12 26 46"; do
  read -r name rgb <<<"$t"
  switch "$name"
  until_ok 3000 centre_is "$rgb"
  # The centre turns before the switch transition has finished drawing the new sheet.
  sleep 0.3
  check "$name: the paper at $cx,$cy is $rgb ($(mean_at "$cx" "$cy" 10 10))" centre_is "$rgb"
  case $name in
    artboard)
      dot_shown() { grim -s 1 -t ppm -g "$((cx - 5)),$((cy - 5)) 4x4" - | has_rgb 180 186 196 12; }
      check "artboard: a dot #B4BAC4 sits at $((cx - 3)),$((cy - 3))" dot_shown
      ;;
    blueprint)
      gx=$((ox + w / 2 / 80 * 80)) gy=$((oy + h / 2 / 80 * 80 + 8))
      read -r lr lg lb < <(mean_at "$gx" "$gy" 1 1)
      read -r cr cg cb < <(mean_at "$((gx + 8))" "$gy" 1 1)
      check "blueprint: the major line at x $gx ($lr $lg $lb) is brighter than the cell ($cr $cg $cb)" \
        test $((lr + lg + lb - cr - cg - cb)) -ge 30
      crop_mark() { grim -s 1 -t ppm -g "$ox,$oy 24x24" - | has_rgb 127 227 240 12; }
      check "blueprint: the top-left 24x24 holds the crop mark #7FE3F0" crop_mark
      ;;
  esac
done

switch paper
until_ok 3000 centre_is "241 233 216"
no_crop_mark() { ! grim -s 1 -t ppm -g "$ox,$oy 24x24" - | has_rgb 127 227 240 12; }
check "paper again: the top-left 24x24 holds no #7FE3F0" no_crop_mark

errors=$(journalctl --user -u "$DOTS_DEV_UNIT" --no-pager -o cat | grep -E 'Failed to load|ShaderEffect|QShader|\.qsb')
[ -n "$errors" ] && echo "$errors"
check "the shell's journal has no load or shader error" test -z "$errors"

exit $((fails > 0))
}
