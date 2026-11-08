#!/usr/bin/env bash
# Under a colorscheme two tiled foots are two sections of one canvas with no gap between them: the unfocused one has no frame, the focused one only a 1 px edge in the dots' line colour.
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

# The row a quarter down, clear of the prompts, from the left strut to the right one: the pixels that are neither the paper the two foots paint nor the line colour, within 8 per channel, and how many are the line. A gap would show the desk's field; the focused foot's edge is its two 1 px sides.
read_row() {
  node -e '
    const fs = require("fs");
    const tokens = JSON.parse(fs.readFileSync(process.argv[2], "utf8")).color;
    const rgb = (s) => [1, 3, 5].map((i) => parseInt(s.slice(i, i + 2), 16));
    const lineRgb = rgb(tokens.line);
    const paper = tokens.paper;
    const b = fs.readFileSync(process.argv[1]);
    const head = b.toString("latin1").match(/^P6\s+(\d+)\s+(\d+)\s+(\d+)\s/);
    const w = +head[1], h = +head[2], px = b.subarray(head[0].length);
    const want = [1, 3, 5].map((i) => parseInt(paper.slice(i, i + 2), 16));
    const y = Math.floor(h / 4);
    const off = [], line = [];
    const near = (p, c) => p.every((v, i) => Math.abs(v - c[i]) <= 8);
    for (let x = 32; x < w - 32; x++) {
      const p = [0, 1, 2].map((i) => px[(y * w + x) * 3 + i]);
      if (near(p, lineRgb)) line.push(x);
      else if (!near(p, want)) off.push(x);
    }
    console.log(JSON.stringify({ width: w, off: off.length, first: off.slice(0, 5), line }));
  ' "$shot" "$XDG_STATE_HOME/dots/theme-out/shell.json"
}
row=$(read_row)
echo "row: $row"
# Every tile keeps a 1 px border slot, clear on an unfocused one, so its edge shows the desk; a clear foot shows the desk there anyway, so only these solid test foots see it. A gap would be the desk 28 px wide.
check "two tiled foots meet with no gap: the row across both is their ground but for the unfocused one's clear 1 px edges" jq -e '.off <= 2' <<<"$row"
check "only the focused foot shows an edge, its two 1 px sides in the line colour" jq -e '(.line | length) == 2' <<<"$row"

exit $((fails > 0))
}
