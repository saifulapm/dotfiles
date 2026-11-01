#!/usr/bin/env bash
# Hi-Fi's brushed paper: its mean is #1D2021, it varies down a column far more than along a row, it never redraws, and at scale 1.25 no column repeats.
{
source "$(dirname "$0")/lib.sh"
shots=$(mktemp -d)
cleanup() { rm -rf "$shots"; }

paper_layer() { niri msg -j layers | jq -e 'any(.[]; .namespace == "dots-paper" and .layer == "Background")' >/dev/null; }
until_ok 5000 paper_layer
until_ok 5000 shell_status >/dev/null

near() { local a b; read -r -a a <<<"$1"; read -r -a b <<<"$2"; for i in 0 1 2; do ((a[i] - b[i] <= $3 && b[i] - a[i] <= $3)) || return 1; done; }
switch() {
  node "$repo/shell/lib/theme-render.mjs" "$1" >/dev/null
  printf '%s\n' "$1" >"$XDG_STATE_HOME/dots/theme"
}

# The band from a tenth to a quarter of the way down, three quarters wide: under the bar and the island, above the passage centred on the desk.
region() {
  local ox oy w h
  read -r ox oy w h < <(niri msg -j outputs | jq -r 'first(.[]).logical | "\(.x) \(.y) \(.width) \(.height)"')
  echo "$((ox + w / 8)),$((oy + h / 10)) $((w * 3 / 4))x$((h / 4 - h / 10))"
}

# Prints "r g b vertical horizontal": the mean colour, and the mean absolute difference of each pixel's channels from the pixel below it and from the one to its right.
stats() {
  node -e '
    const b = require("fs").readFileSync(process.argv[1]);
    const head = b.toString("latin1").match(/^P6\s+(\d+)\s+(\d+)\s+(\d+)\s/);
    const w = +head[1], h = +head[2], px = b.subarray(head[0].length);
    const sum = [0, 0, 0];
    let v = 0, nv = 0, hz = 0, nh = 0;
    for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) for (let c = 0; c < 3; c++) {
      const i = (y * w + x) * 3 + c;
      sum[c] += px[i];
      if (y + 1 < h) { v += Math.abs(px[i] - px[i + w * 3]); nv++; }
      if (x + 1 < w) { hz += Math.abs(px[i] - px[i + 3]); nh++; }
    }
    console.log(sum.map((s) => Math.round(s / (w * h))).join(" "), (v / nv).toFixed(3), (hz / nh).toFixed(3));
  ' "$1"
}

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

switch hi-fi
hifi_up() { near "$(grim -s 1 -t ppm -g "$(region)" - | mean_rgb)" "29 32 33" 4; }
until_ok 3000 hifi_up
# The dial sweep runs 220 ms and the lamps warm up after it, so the sheet is at rest well within a second.
sleep 1

grim -s 1 -t ppm -g "$(region)" "$shots/a.ppm"
read -r r g b vert horiz < <(stats "$shots/a.ppm")
check "the brushed paper's mean ($r $g $b) is within 4 of 29 32 33" near "$r $g $b" "29 32 33" 4
streaky() { node -e 'const [v, h] = process.argv.slice(1).map(Number); process.exit(v >= 0.5 && v >= 3 * h ? 0 : 1)' "$vert" "$horiz"; }
check "brightness varies down a column ($vert) at least 3 times more than along a row ($horiz)" streaky

sleep 2
grim -s 1 -t ppm -g "$(region)" "$shots/b.ppm"
check "two grims 2 s apart are byte-identical" cmp -s "$shots/a.ppm" "$shots/b.ppm"

name=$(niri msg -j outputs | jq -r 'first(.[]).name')
niri msg output "$name" scale 1.25
scaled() { niri msg -j outputs | jq -e 'first(.[]).logical.scale == 1.25' >/dev/null; }
check "the nested output $name takes scale 1.25" until_ok 3000 scaled
# A sheet drawn before the rescale keeps its old physical width, so Paper and then Hi-Fi draw a fresh one at 1.25, as at a 1.25 startup.
switch paper
paper_up() { near "$(grim -t ppm -g "$(region)" - | mean_rgb)" "241 233 216" 6; }
until_ok 3000 paper_up
switch hi-fi
until_ok 3000 hifi_up
sleep 1
# No -s, so grim captures the physical pixels the shader drew.
grim -t ppm -g "$(region)" "$shots/c.ppm"
period=$(column_period "$shots/c.ppm")
check "at scale 1.25 no column repeats with a period under 64 px (found: $period)" test "$period" = none

errors=$(journalctl --user -u "$DOTS_DEV_UNIT" --no-pager -o cat | grep -E 'Failed to load|ShaderEffect|QShader|\.qsb')
[ -n "$errors" ] && echo "$errors"
check "the shell's journal has no load or shader error" test -z "$errors"

exit $((fails > 0))
}
