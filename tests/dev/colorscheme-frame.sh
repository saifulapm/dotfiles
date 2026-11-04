#!/usr/bin/env bash
# Under a colorscheme two tiled foots sit on the paper framed square in 1 px, ink on the focused one and line on the other, with no pixel darker than the paper within 20 px outside either frame; the old Artboard's shadow (#15171B2E, softness 40, y 18) put into niri.kdl after the switch fails the last check.
{
export DOTS_DEV_SCHEME=${DOTS_DEV_SCHEME-gruvbox-dark}
source "$(dirname "$0")/lib.sh"
unset TMUX

until_ok 5000 shell_status >/dev/null
niri msg action spawn -- foot -c /dev/null
two_windows() { test "$(niri msg -j windows | jq length)" = 2; }
niri msg action spawn -- foot -c /dev/null
until_ok 5000 two_windows
# The nested foots start on foot's own colours; a switch to the scheme recolours them.
if [ -n "$DOTS_DEV_SCHEME" ]; then
  "$repo/bin/dots" colorscheme "$DOTS_DEV_SCHEME" >/dev/null
  until_ok 3000 eval "shell_status | jq -e '.theme == \"$DOTS_DEV_SCHEME\" and .transition == \"\"' >/dev/null"
fi
sleep 1
shot=$DOTS_DEV_DIR/frame.ppm
grim -s 1 -t ppm "$shot"

# Each tile along the row a quarter down and its own middle column: its two edges' colours, and the darkest pixel within 20 px outside them.
read_frames() {
  node -e '
    const fs = require("fs");
    const t = JSON.parse(fs.readFileSync(process.argv[2], "utf8")).color;
    const b = fs.readFileSync(process.argv[1]);
    const head = b.toString("latin1").match(/^P6\s+(\d+)\s+(\d+)\s+(\d+)\s/);
    const w = +head[1], h = +head[2], px = b.subarray(head[0].length);
    const at = (x, y) => [0, 1, 2].map((i) => px[(y * w + x) * 3 + i]);
    const hex = (s) => [1, 3, 5].map((i) => parseInt(s.slice(i, i + 2), 16));
    const near = (a, c) => a.every((v, i) => Math.abs(v - c[i]) <= 8);
    const lum = (a) => 0.2126 * a[0] + 0.7152 * a[1] + 0.0722 * a[2];
    const [paper, surface, ink, line] = [t.paper, t.surface, t.ink, t.line].map(hex);
    const tileish = (a) => near(a, surface) || near(a, ink) || near(a, line);
    const name = (a) => (near(a, ink) ? "ink" : near(a, line) ? "line" : a.map((v) => v.toString(16).padStart(2, "0")).join(""));
    // Runs of tile colour at least 100 px long, so a dot on the paper is never one.
    const runs = (n, get) => {
      const found = [];
      for (let i = 0, start = -1; i <= n; i++) {
        const on = i < n && tileish(get(i));
        if (on && start < 0) start = i;
        if (!on && start >= 0) { if (i - start >= 100) found.push([start, i - 1]); start = -1; }
      }
      return found;
    };
    const darkest = (n, get, a, b) => {
      let worst = Infinity;
      for (let i = Math.max(0, a - 20); i < a; i++) worst = Math.min(worst, lum(get(i)));
      for (let i = b + 1; i <= Math.min(n - 1, b + 20); i++) worst = Math.min(worst, lum(get(i)));
      return worst;
    };
    // The frame is the pixel just outside the surface, so a dot touching the tile never moves it.
    const frame = (get, a, b) => {
      let lo = a, hi = b;
      while (lo < b && !near(get(lo), surface)) lo++;
      while (hi > a && !near(get(hi), surface)) hi--;
      return [lo - 1, hi + 1];
    };
    // A quarter down, clear of the passage box the shell draws in the gap at mid-height.
    const y = Math.floor(h / 4);
    const out = runs(w, (x) => at(x, y)).map(([ra, rb]) => {
      const [a, b] = frame((x) => at(x, y), ra, rb);
      const x = Math.floor((a + b) / 2);
      const col = runs(h, (yy) => at(x, yy)).find(([c, d]) => c <= y && y <= d) ?? [y, y];
      const [top, bottom] = frame((yy) => at(x, yy), col[0], col[1]);
      // The four sides at their middles, then two corners, which a rounded frame leaves to the paper.
      const edges = [at(a, y), at(b, y), at(x, top), at(x, bottom), at(a, top), at(b, bottom)].map(name);
      const dark = Math.min(darkest(w, (xx) => at(xx, y), a, b), darkest(h, (yy) => at(x, yy), top, bottom));
      return { x: [a, b], y: [top, bottom], edges, darker: dark < lum(paper) - 0.5 };
    });
    console.log(JSON.stringify(out));
  ' "$shot" "$XDG_STATE_HOME/dots/theme-out/shell.json"
}
frames=$(read_frames)
echo "tiles: $frames"
check "two tiles lie across the screen a quarter down" jq -e 'length == 2' <<<"$frames"
check "one tile is framed in ink on all four sides and square at its corners" jq -e 'map(select(.edges == ["ink","ink","ink","ink","ink","ink"])) | length == 1' <<<"$frames"
check "the other is framed in line on all four sides and square at its corners" jq -e 'map(select(.edges == ["line","line","line","line","line","line"])) | length == 1' <<<"$frames"
check "no pixel within 20 px outside either frame is darker than the paper" jq -e 'all(.[]; .darker == false)' <<<"$frames"

exit $((fails > 0))
}
