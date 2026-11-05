#!/usr/bin/env bash
# Every colorscheme locks into the one lock, Artboard's card: under rose-pine-dawn the card is #FAF4ED, the clock #575279 and the date under it, and each of the five schemes draws the same card in its own surface and ink.
{
export DOTS_DEV_SCHEME=rose-pine-dawn
source "$(dirname "$0")/lib.sh"
unset TMUX

# A killed instance's socket lingers, so every call goes to the unit's current process.
shell_pid() { systemctl --user show -p MainPID --value "$DOTS_DEV_UNIT"; }
lock_state() { timeout 0.5 env -u QS_CONFIG_PATH qs ipc --pid "$(shell_pid)" call lock state 2>/dev/null; }
state_is() { lock_state | jq -e "$@" >/dev/null 2>&1; }
rest_in() { shell_status | jq -e --arg t "$1" '.theme == $t and .transition == ""' >/dev/null; }
locked_shown() { state_is '.locked and .secure'; }
unlocked() { state_is '.locked == false'; }
lock() {
  niri msg action spawn -- dots-call lock lock
  until_ok 3000 locked_shown
}
unlock() {
  wtype -- dots-test-pass
  wtype -k Return
  until_ok 3000 unlocked
}
# A failed check must not leave the nested session locked.
cleanup() { locked_shown && unlock; }

hex_rgb() { printf '%d %d %d' "0x${1:1:2}" "0x${1:3:2}" "0x${1:5:2}"; }
toml_colour() { sed -n "s/^$2 = \"\(#[0-9A-Fa-f]*\)\"$/\1/p" "$repo/colorschemes/$1.toml"; }
# The card's fill, 4 x 4 px inside its top-left, as "r g b".
card_rgb() { grim -s 1 -t ppm -g "$(((ow - 460 + 1) / 2 + 24)),$((oh * 3 / 10 + 8)) 4x4" - | mean_rgb; }
near_rgb() {
  local a b
  read -r -a a <<<"$1"
  read -r -a b <<<"$2"
  for i in 0 1 2; do ((a[i] - b[i] <= 3 && b[i] - a[i] <= 3)) || return 1; done
}
# Pixels near r g b (within 40) in three one-pixel rows across the clock, from its box in the lock's state.
clock_ink() {
  local f total=0 n
  for f in 0.35 0.55 0.75; do
    n=$(grim -s 1 -t ppm -g "$(lock_state | jq -r --argjson f "$f" '.clockBox | "\(.x | floor),\(.y + .h * $f | floor) \(.w | floor)x1"')" - | node -e '
      const b = require("fs").readFileSync(0), want = process.argv.slice(1).map(Number);
      const head = b.toString("latin1").match(/^P6\s+(\d+)\s+(\d+)\s+(\d+)\s/), px = b.subarray(head[0].length);
      let n = 0;
      for (let i = 0; i < head[1] * head[2]; i++) if ([0, 1, 2].every((k) => Math.abs(px[i * 3 + k] - want[k]) <= 40)) n++;
      console.log(n);
    ' $1)
    total=$((total + n))
  done
  echo "$total"
}

until_ok 5000 rest_in rose-pine-dawn
read -r ow oh < <(niri msg -j outputs | jq -r 'first(.[]).logical | "\(.width) \(.height)"')

lock
check "rose-pine-dawn: the lock draws Artboard's card with a 96 px Maple Mono clock in #575279 ($(lock_state | jq -c '[.look, .clockFamily, .clockPx, .clockFill]'))" state_is '.look == "card" and .clockFamily == "Maple Mono" and .clockPx == 96 and (.clockFill | ascii_downcase) == "#575279"'
fill=$(card_rgb)
check "rose-pine-dawn: the card's fill reads #FAF4ED ($fill)" near_rgb "$fill" "250 244 237"
ink=$(clock_ink "87 82 121")
check "rose-pine-dawn: rows across the clock draw #575279 ($ink px)" test "$ink" -gt 10
check "rose-pine-dawn: the date sits on the card under the clock ($(lock_state | jq -c '[.dateText, .dateBox.y - (.clockBox.y + .clockBox.h)]'))" \
  state_is --argjson ow "$ow" --argjson oh "$oh" '.dateText != "" and .dateBox.y >= .clockBox.y + .clockBox.h and .dateBox.x >= ($ow - 460) / 2 and .dateBox.x + .dateBox.w <= ($ow + 460) / 2 and .dateBox.y + .dateBox.h <= .fieldBox.y'
unlock
check "rose-pine-dawn: the test password unlocks" unlocked

for s in artboard catppuccin-mocha github-light gruvbox-dark rose-pine-dawn; do
  "$repo/bin/dots" colorscheme "$s" >/dev/null
  until_ok 3000 rest_in "$s"
  lock
  ink_hex=$(toml_colour "$s" ink)
  surface=$(hex_rgb "$(toml_colour "$s" surface)")
  check "$s: the lock is the same card, its clock in $ink_hex ($(lock_state | jq -c '[.look, .clockFill]'))" state_is --arg i "$ink_hex" '.look == "card" and (.clockFill | ascii_downcase) == ($i | ascii_downcase)'
  fill=$(card_rgb)
  check "$s: the card's fill is the scheme's surface ($fill, want $surface)" near_rgb "$fill" "$surface"
  ink=$(clock_ink "$(hex_rgb "$ink_hex")")
  check "$s: the clock's ink reads on the card ($ink px)" test "$ink" -gt 10
  unlock
done

exit $((fails > 0))
}
