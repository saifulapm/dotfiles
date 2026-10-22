#!/usr/bin/env bash
# The outgoing theme's switch transition: seen mid-way on screen, done by 350 ms from the spawn (dots theme about 75 ms, the rebinding about 40, the 220 ms scan; #ANBVSPFJ), and nothing left running.
{
source "$(dirname "$0")/lib.sh"
unset TMUX

paper_layer() { niri msg -j layers | jq -e 'any(.[]; .namespace == "dots-paper" and .layer == "Background")' >/dev/null; }
until_ok 5000 paper_layer
until_ok 5000 shell_status >/dev/null

read -r ox oy w h < <(niri msg -j outputs | jq -r 'first(.[]).logical | "\(.x) \(.y) \(.width) \(.height)"')
# A quarter in, clear of the island, and 3 px into a 16 px cell, so no dot or grid line falls in a band.
x=$((ox + w / 4 / 16 * 16 + 3))
top=67 mid=$((h / 2 / 16 * 16 + 3)) bottom=$(((h - 60) / 16 * 16 + 3))

# One grim of a 1 px column, so top, middle and bottom come from the same frame; prints 9 numbers.
bands() {
  grim -s 1 -t ppm -g "$x,$oy 1x$h" - | node -e '
    const buf = require("fs").readFileSync(0);
    const head = buf.toString("latin1").match(/^P6\s+(\d+)\s+(\d+)\s+(\d+)\s/);
    const px = buf.subarray(head[0].length);
    const out = [];
    for (const y0 of process.argv.slice(1).map(Number)) {
      const sum = [0, 0, 0];
      for (let y = y0; y < y0 + 10; y++) for (let c = 0; c < 3; c++) sum[c] += px[y * 3 + c];
      out.push(...sum.map((s) => Math.round(s / 10)));
    }
    console.log(out.join(" "));
  ' "$top" "$mid" "$bottom"
}
near12() { (($1 - $4 <= 12 && $4 - $1 <= 12 && $2 - $5 <= 12 && $5 - $2 <= 12 && $3 - $6 <= 12 && $6 - $3 <= 12)); }

declare -A rgb=([paper]="241 233 216" [artboard]="228 230 234" [blueprint]="12 26 46")

# Switches to $2 in the background and grabs the column until 250 ms; then the frame at 350 ms.
seen=() final=""
switch_from() {
  local start t pid
  start=$(now_ms)
  "$repo/bin/dots" theme "$2" >/dev/null &
  pid=$!
  seen=()
  while t=$(($(now_ms) - start)) && ((t < 250)); do
    seen+=("$t $(bands)")
  done
  while (($(now_ms) - start < 350)); do sleep 0.005; done
  final=$(bands)
  wait "$pid"
}

# Exits 0 if a grab in $seen had the top near $1 and the bottom near $2; else prints the grabs.
mix_seen() {
  local s
  for s in "${seen[@]}"; do
    read -r t tr tg tb _ _ _ br bg bb <<<"$s"
    # shellcheck disable=SC2086 # each colour is three numbers
    near12 "$tr" "$tg" "$tb" $1 && near12 "$br" "$bg" "$bb" $2 && return 0
  done
  printf '     grab (ms, top, middle, bottom): %s\n' "${seen[@]}" >&2
  return 1
}
all_are() {
  local v
  read -r -a v <<<"$final"
  near12 "${v[@]:0:3}" "$@" && near12 "${v[@]:3:3}" "$@" && near12 "${v[@]:6:3}" "$@"
}

"$repo/bin/dots" theme paper >/dev/null
all_are_now() { final=$(bands); all_are "$@"; }
until_ok 3000 all_are_now ${rgb[paper]}
check "the start is all paper ($final)" all_are ${rgb[paper]}

switch_from paper blueprint
check "paper to blueprint: a grab has cream on top and navy below (the sheet slides up)" mix_seen "${rgb[paper]}" "${rgb[blueprint]}"
check "paper to blueprint: all blueprint by 350 ms ($final)" all_are ${rgb[blueprint]}

switch_from blueprint artboard
check "blueprint to artboard: a grab has grey on top and navy below (the scan line sweeps down)" mix_seen "${rgb[artboard]}" "${rgb[blueprint]}"
check "blueprint to artboard: all artboard by 350 ms ($final)" all_are ${rgb[artboard]}

switch_from artboard paper
check "artboard to paper: all paper by 350 ms ($final)" all_are ${rgb[paper]}

# The zoom pulls the canvas off the screen edges, so the edge band must fade like the middle, never swing back.
edge_px() { grim -s 1 -t ppm -g "7,600 1x1" - | tail -c3 | od -An -tu1; }
"$repo/bin/dots" theme artboard >/dev/null
sleep 0.6
"$repo/bin/dots" theme blueprint >/dev/null &
sw=$!
edge=()
start=$(now_ms)
while (($(now_ms) - start < 400)); do edge+=("$(edge_px)"); done
wait "$sw"
# Blueprint is darker on every channel, so a red value that rises again after falling is the flash.
edge_monotonic() {
  local px r low=999
  for px in "${edge[@]}"; do
    read -r r _ <<<"$px"
    ((r > low + 6)) && return 1
    ((r < low)) && low=$r
  done
  return 0
}
check "artboard to blueprint: the screen edge fades without swinging back (${#edge[@]} frames)" edge_monotonic

# Back to paper while the slide to blueprint still runs: paper must be what stays.
"$repo/bin/dots" theme blueprint >/dev/null
"$repo/bin/dots" theme paper >/dev/null
sleep 0.8
final=$(bands)
check "paper, blueprint, paper inside one transition ends on paper ($final)" all_are ${rgb[paper]}

timers_one() { shell_status | jq -e '.timers == 1' >/dev/null; }
check "after the transitions status reports timers 1" timers_one

errors=$(journalctl --user -u "$DOTS_DEV_UNIT" --no-pager -o cat | grep -E 'Failed to load|ShaderEffect|QShader|\.qsb|Paper.qml|PaperFill.qml')
[ -n "$errors" ] && echo "$errors"
check "the shell's journal has no load or shader error" test -z "$errors"

exit $((fails > 0))
}
