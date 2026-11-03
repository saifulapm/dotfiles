#!/usr/bin/env bash
# Frost's paper: its centre is clear #2E3440, every corner is brighter with frost, it never redraws, and at scale 1.25 no column repeats.
{
source "$(dirname "$0")/lib.sh"
shots=$(mktemp -d)
cleanup() { rm -rf "$shots"; }

paper_layer() { niri msg -j layers | jq -e 'any(.[]; .namespace == "dots-paper" and .layer == "Background")' >/dev/null; }
until_ok 5000 paper_layer
until_ok 5000 shell_status >/dev/null

near() { local a b; read -r -a a <<<"$1"; read -r -a b <<<"$2"; for i in 0 1 2; do ((a[i] - b[i] <= $3 && b[i] - a[i] <= $3)) || return 1; done; }
# Exits 0 if each channel of $1 is at least $3 above the same channel of $2.
brighter() { local a b; read -r -a a <<<"$1"; read -r -a b <<<"$2"; for i in 0 1 2; do ((a[i] - b[i] >= $3)) || return 1; done; }
switch() {
  node "$repo/shell/lib/theme-render.mjs" "$1" >/dev/null
  printf '%s\n' "$1" >"$XDG_STATE_HOME/dots/theme"
}

box() { niri msg -j outputs | jq -r 'first(.[]).logical | "\(.x) \(.y) \(.width) \(.height)"'; }
# The middle of the paper: a 400 x 300 box centred across, from a tenth of the way down, between the margins and the passage centred on the desk.
centre() { local ox oy w h; read -r ox oy w h < <(box); echo "$((ox + w / 2 - 200)),$((oy + h / 10)) 400x300"; }
# The 120 x 120 corner $1 (tl, tr, bl, br). The margins draw their text and rule in the top 44 px, so the top corners start just below them.
corner() {
  local ox oy w h x y
  read -r ox oy w h < <(box)
  case $1 in tl | bl) x=$ox ;; *) x=$((ox + w - 120)) ;; esac
  case $1 in tl | tr) y=$((oy + 44)) ;; *) y=$((oy + h - 120)) ;; esac
  echo "$x,$y 120x120"
}
# The left 24th of the output, from a quarter to three quarters down: frost covers every column of it, clear of the margins.
strip() { local ox oy w h; read -r ox oy w h < <(box); echo "$ox,$((oy + h / 4)) $((w / 24))x$((h / 2))"; }

# An exact-repeat test: prints the shortest period under 64 px at which some column has every pixel equal to the one p rows below it, or "none"; random rows never match all the way down, while a tiled pattern, or a flat sheet at period 1, does.
column_period() {
  node -e '
    const b = require("fs").readFileSync(process.argv[1]);
    const head = b.toString("latin1").match(/^P6\s+(\d+)\s+(\d+)\s+(\d+)\s/);
    const w = +head[1], h = +head[2], px = b.subarray(head[0].length);
    const at = (x, y) => (y * w + x) * 3;
    for (let p = 1; p < 64; p++) for (let x = 0; x < w; x++) {
      let same = true;
      for (let y = 0; same && y + p < h; y++) {
        const i = at(x, y), j = at(x, y + p);
        same = px[i] === px[j] && px[i + 1] === px[j + 1] && px[i + 2] === px[j + 2];
      }
      if (same) { console.log(p, "at column", x); process.exit(0); }
    }
    console.log("none");
  ' "$1"
}

switch frost
frost_up() { near "$(grim -s 1 -t ppm -g "$(centre)" - | mean_rgb)" "46 52 64" 2; }
until_ok 3000 frost_up
# The switch transition ends well within a second, so the sheet is at rest after it.
sleep 1

grim -s 1 -t ppm -g "$(centre)" "$shots/a.ppm"
mid=$(mean_rgb <"$shots/a.ppm")
check "the centre 400 x 300 ($mid) is within 2 of 46 52 64" near "$mid" "46 52 64" 2
for c in tl tr bl br; do
  rgb=$(grim -s 1 -t ppm -g "$(corner "$c")" - | mean_rgb)
  check "the $c corner at $(corner "$c") ($rgb) is brighter than the centre ($mid) by 6 or more" brighter "$rgb" "$mid" 6
done

# The whole output under the margins, whose clock may tick within 2 s.
below() { local ox oy w h; read -r ox oy w h < <(box); echo "$ox,$((oy + 44)) ${w}x$((h - 44))"; }
grim -s 1 -t ppm -g "$(below)" "$shots/full-a.ppm"
sleep 2
grim -s 1 -t ppm -g "$(below)" "$shots/full-b.ppm"
check "two grims 2 s apart are byte-identical" cmp -s "$shots/full-a.ppm" "$shots/full-b.ppm"

name=$(niri msg -j outputs | jq -r 'first(.[]).name')
niri msg output "$name" scale 1.25
scaled() { niri msg -j outputs | jq -e 'first(.[]).logical.scale == 1.25' >/dev/null; }
check "the nested output $name takes scale 1.25" until_ok 3000 scaled
# A sheet drawn before the rescale keeps its old physical width, so Paper and then Frost draw a fresh one at 1.25, as at a 1.25 startup.
switch paper
paper_up() { near "$(grim -t ppm -g "$(centre)" - | mean_rgb)" "241 233 216" 6; }
until_ok 3000 paper_up
switch frost
until_ok 3000 frost_up
sleep 1
# No -s, so grim captures the physical pixels the shader drew.
grim -t ppm -g "$(strip)" "$shots/c.ppm"
period=$(column_period "$shots/c.ppm")
check "at scale 1.25 no column repeats with a period under 64 px (found: $period)" test "$period" = none

errors=$(journalctl --user -u "$DOTS_DEV_UNIT" --no-pager -o cat | grep -E 'Failed to load|ShaderEffect|QShader|\.qsb')
[ -n "$errors" ] && echo "$errors"
check "the shell's journal has no load or shader error" test -z "$errors"

exit $((fails > 0))
}
