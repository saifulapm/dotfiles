#!/usr/bin/env bash
# Hi-Fi's theme switch: a red pointer sweeps left to right whether Hi-Fi comes in or goes out, done by 300 ms from the spawn (with the scan, Blueprint to Hi-Fi read transition "" 236 to 282 ms after the spawn, a 16 to 62 ms handover), while the other themes keep their own motion.
{
source "$(dirname "$0")/lib.sh"
unset TMUX

paper_layer() { niri msg -j layers | jq -e 'any(.[]; .namespace == "dots-paper" and .layer == "Background")' >/dev/null; }
until_ok 5000 paper_layer
until_ok 5000 shell_status >/dev/null

read -r ox oy w h < <(niri msg -j outputs | jq -r 'first(.[]).logical | "\(.x) \(.y) \(.width) \(.height)"')
# A quarter down, under the bar and the island and above the passage, and 3 px into a 16 px cell, so no grid line falls on it.
y=$((oy + h / 4 / 16 * 16 + 3))

# One grim of a 1 px row; prints the mean colour of its left, middle and right bands (each 5 % of the width), from the columns 3 px into a 16 px cell.
bands() {
  grim -s 1 -t ppm -g "$ox,$y ${w}x1" - | node -e '
    const buf = require("fs").readFileSync(0);
    const head = buf.toString("latin1").match(/^P6\s+(\d+)\s+(\d+)\s+(\d+)\s/);
    const w = +head[1], px = buf.subarray(head[0].length);
    const out = [];
    for (const from of [0.02, 0.475, 0.93]) {
      const sum = [0, 0, 0];
      let n = 0;
      for (let x = Math.round(from * w); x < Math.round((from + 0.05) * w); x++) {
        if (x % 16 !== 3) continue;
        for (let c = 0; c < 3; c++) sum[c] += px[x * 3 + c];
        n++;
      }
      out.push(...sum.map((s) => Math.round(s / n)));
    }
    console.log(out.join(" "));
  '
}
near() { (($1 - $4 <= $7 && $4 - $1 <= $7 && $2 - $5 <= $7 && $5 - $2 <= $7 && $3 - $6 <= $7 && $6 - $3 <= $7)); }

declare -A rgb=([paper]="241 233 216" [blueprint]="12 26 46" [hi-fi]="29 32 33")
status_at_rest() { shell_status | jq -e --arg t "$1" '.theme == $t and .transition == ""' >/dev/null; }

# Switches to $1 in the background and grabs the row until 250 ms, while a second loop polls status for 1 s, so a grab never delays the poll that reads "".
kinds="" done_ms="" grabs=() final=""
polls=$(mktemp)
cleanup() { rm -f "$polls"; }
switch_to() {
  local start t pid poller k
  start=$(now_ms)
  "$repo/bin/dots" theme "$1" >/dev/null &
  pid=$!
  while (($(now_ms) - start < 1000)); do echo "$(($(now_ms) - start)) $(shell_status | jq -r '.transition')"; done >"$polls" &
  poller=$!
  kinds="" done_ms="" grabs=()
  while t=$(($(now_ms) - start)) && ((t < 250)); do grabs+=("$t $(bands)"); done
  wait "$pid"
  wait "$poller"
  # Each poll's time is when it started; the end is the first "" after a kind.
  while read -r t k; do
    if [ -n "$k" ]; then
      [[ " $kinds " == *" $k "* ]] || kinds="$kinds $k"
    elif [ -n "$kinds" ]; then
      done_ms=$t
      break
    fi
  done <"$polls"
  final=$(bands)
  kinds=${kinds# }
}

# Exits 0 if a grab had the left band near $1 and the right band near $2; else prints the grabs.
split_seen() {
  local s
  for s in "${grabs[@]}"; do
    read -r _ lr lg lb _ _ _ rr rg rb <<<"$s"
    # shellcheck disable=SC2086 # each colour is three numbers
    near "$lr" "$lg" "$lb" $1 10 && near "$rr" "$rg" "$rb" $2 10 && return 0
  done
  printf '     grab (ms, left, middle, right): %s\n' "${grabs[@]}" >&2
  return 1
}
all_are() {
  local v
  read -r -a v <<<"$final"
  near "${v[@]:0:3}" "$@" 10 && near "${v[@]:3:3}" "$@" 10 && near "${v[@]:6:3}" "$@" 10
}
within() { [ -n "$done_ms" ] && ((done_ms <= 300)); }

"$repo/bin/dots" theme blueprint >/dev/null
until_ok 3000 status_at_rest blueprint
sleep 0.5

switch_to hi-fi
check "blueprint to hi-fi: status reports transition sweep (saw: $kinds)" test "$kinds" = sweep
check "blueprint to hi-fi: transition reads \"\" by 300 ms from the spawn (at ${done_ms:-never} ms)" within
check "blueprint to hi-fi: a row grab has hi-fi dark left of the pointer and blueprint navy right of it" split_seen "${rgb[hi-fi]}" "${rgb[blueprint]}"
check "blueprint to hi-fi: the row ends all hi-fi ($final)" all_are ${rgb[hi-fi]}
sleep 0.5

switch_to paper
check "hi-fi to paper: status reports transition sweep (saw: $kinds)" test "$kinds" = sweep
check "hi-fi to paper: transition reads \"\" by 300 ms from the spawn (at ${done_ms:-never} ms)" within
check "hi-fi to paper: the row ends all paper cream ($final)" all_are ${rgb[paper]}
sleep 0.5

switch_to blueprint
check "paper to blueprint: still the slide (saw: $kinds)" test "$kinds" = slide
check "paper to blueprint: the row ends all blueprint ($final)" all_are ${rgb[blueprint]}
sleep 0.5

"$repo/bin/dots" theme artboard >/dev/null &
pid=$!
artboard_kinds=""
start=$(now_ms)
while (($(now_ms) - start < 400)); do
  k=$(shell_status | jq -r '.transition')
  [ -n "$k" ] && [[ " $artboard_kinds " != *" $k "* ]] && artboard_kinds="$artboard_kinds $k"
done
wait "$pid"
check "blueprint to artboard: still the scan (saw:$artboard_kinds)" test "$artboard_kinds" = " scan"

timers_one() { shell_status | jq -e '.timers == 1' >/dev/null; }
check "after the switches status reports timers 1" timers_one
pointer_null() { shell_status | jq -e '.pointer == null' >/dev/null; }
check "after the switches status reports pointer null" pointer_null

errors=$(journalctl --user -u "$DOTS_DEV_UNIT" --no-pager -o cat | grep -E 'Failed to load|ShaderEffect|QShader|\.qsb|Paper.qml|PaperFill.qml')
[ -n "$errors" ] && echo "$errors"
check "the shell's journal has no load or shader error" test -z "$errors"

exit $((fails > 0))
}
