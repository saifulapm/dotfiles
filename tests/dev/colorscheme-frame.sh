#!/usr/bin/env bash
# Under a colorscheme two tiled foots are two sections of one canvas: no frame on either, the focused one too, and no gap between them.
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

# The row a quarter down, clear of the prompts, from the left strut to the right one: the pixels that are not the paper the two foots paint, within 8 per channel. A frame would show its line there, and a gap the desk's field.
read_row() {
  node -e '
    const fs = require("fs");
    const paper = JSON.parse(fs.readFileSync(process.argv[2], "utf8")).color.paper;
    const b = fs.readFileSync(process.argv[1]);
    const head = b.toString("latin1").match(/^P6\s+(\d+)\s+(\d+)\s+(\d+)\s/);
    const w = +head[1], h = +head[2], px = b.subarray(head[0].length);
    const want = [1, 3, 5].map((i) => parseInt(paper.slice(i, i + 2), 16));
    const y = Math.floor(h / 4);
    const off = [];
    for (let x = 32; x < w - 32; x++) {
      const p = [0, 1, 2].map((i) => px[(y * w + x) * 3 + i]);
      if (p.some((v, i) => Math.abs(v - want[i]) > 8)) off.push(x);
    }
    console.log(JSON.stringify({ width: w, off: off.length, first: off.slice(0, 5) }));
  ' "$shot" "$XDG_STATE_HOME/dots/theme-out/shell.json"
}
row=$(read_row)
echo "row: $row"
check "two tiled foots meet with no frame and no gap: the row across both is their ground, unbroken" jq -e '.off == 0' <<<"$row"

exit $((fails > 0))
}
