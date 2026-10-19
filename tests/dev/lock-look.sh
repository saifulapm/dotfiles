#!/usr/bin/env bash
# Each theme locks into its own lock design: Paper's big serif clock, Artboard's card, Blueprint's hollow outlined clock.
source "$(dirname "$0")/lib.sh"
unset TMUX

# A killed instance's socket lingers, so every call goes to the unit's current process.
shell_pid() { systemctl --user show -p MainPID --value "$DOTS_DEV_UNIT"; }
lock_state() { timeout 0.5 env -u QS_CONFIG_PATH qs ipc --pid "$(shell_pid)" call lock state 2>/dev/null; }
state_is() { lock_state | jq -e "$@" >/dev/null 2>&1; }
status_theme() { shell_status | jq -e --arg t "$1" '.theme == $t' >/dev/null; }
locked_shown() { state_is '.locked and .secure'; }
unlocked() { state_is '.locked == false'; }
unlock() {
  wtype -- dots-test-pass
  wtype -k Return
  until_ok 3000 unlocked
}
# A failed check must not leave the nested session locked.
cleanup() { locked_shown && unlock; }

lock_in() {
  "$repo/bin/dots" theme "$1" >/dev/null
  until_ok 2000 status_theme "$1"
  niri msg action spawn -- qs ipc call lock lock
  until_ok 3000 locked_shown
}

# Pixels of a strip near r g b (tol 40), and the longest run of them, as "count run".
near_runs() {
  grim -s 1 -t ppm -g "$1" - | node -e '
    const b = require("fs").readFileSync(0), want = process.argv.slice(1).map(Number);
    const head = b.toString("latin1").match(/^P6\s+(\d+)\s+(\d+)\s+(\d+)\s/), px = b.subarray(head[0].length);
    let n = 0, run = 0, best = 0;
    for (let i = 0; i < head[1] * head[2]; i++) {
      if ([0, 1, 2].every((k) => Math.abs(px[i * 3 + k] - want[k]) <= 40)) { n++; run++; best = Math.max(best, run); } else run = 0;
    }
    console.log(n, best);
  ' "$2" "$3" "$4"
}
# A one-pixel row across the clock at a share of its height, from its box in the lock's state; one row can miss thin digits like 1 and 7, so three are summed.
clock_row() { lock_state | jq -r --argjson f "$1" '.clockBox | "\(.x | floor),\(.y + .h * $f | floor) \(.w | floor)x1"'; }
# Sums near_runs' counts over the three rows and keeps the longest run.
rows_runs() {
  local f n run total=0 longest=0
  for f in 0.35 0.55 0.75; do
    read -r n run < <(near_runs "$(clock_row "$f")" "$@")
    total=$((total + n)) && ((run > longest)) && longest=$run
  done
  echo "$total $longest"
}

until_ok 5000 shell_status >/dev/null
read -r ow oh < <(niri msg -j outputs | jq -r 'first(.[]).logical | "\(.width) \(.height)"')

lock_in paper
check "paper: the lock's clock asks for Instrument Serif at 200 px or more ($(lock_state | jq -c '[.clockFamily, .clockPx]'))" state_is '.clockFamily == "Instrument Serif" and .clockPx >= 200'
check "paper: the clock is ink with no outline" state_is '.look == "print" and (.clockFill | ascii_downcase) == "#1c1915" and .clockStroke == "transparent"'
unlock
check "paper: the test password unlocks" unlocked

lock_in artboard
check "artboard: the lock draws its clock on a card, 96 px bold Inter" state_is '.look == "card" and .clockFamily == "Inter" and .clockPx == 96'
# The card is white and the paper grey, so a pixel inside the card's top-left reads white.
card_white() { local r g b; read -r r g b < <(grim -s 1 -t ppm -g "$(((ow - 460) / 2 + 24)),$((oh * 3 / 10 + 8)) 4x4" - | mean_rgb); ((r > 250 && g > 250 && b > 250)); }
until_ok 2000 card_white
check "artboard: the white card shows at the screen's centre" card_white
unlock

lock_in blueprint
check "blueprint: the clock's fill is transparent and its outline #7FE3F0 ($(lock_state | jq -c '[.clockFill, .clockStroke]'))" state_is '.look == "sheet" and .clockFill == "#00000000" and (.clockStroke | ascii_downcase) == "#7fe3f0"'
read -r cyan cyan_run < <(rows_runs 127 227 240)
read -r ground _ < <(rows_runs 12 26 46)
check "blueprint: rows across the clock have accent ($cyan px) and background ($ground px)" test "$cyan" -gt 10 -a "$ground" -gt 10
# A filled 200 px bold glyph crosses the row in runs of 20 px or more; an outline only in thin ones.
check "blueprint: the clock's strokes are thin outlines, not fills (longest accent run $cyan_run px)" test "$cyan_run" -le 8
unlock
check "blueprint: the test password unlocks" unlocked

"$repo/bin/dots" theme paper >/dev/null
exit $((fails > 0))
