#!/usr/bin/env bash
# Each theme locks into its own lock design: Paper's big serif clock, Artboard's card, Blueprint's hollow outlined clock, Hi-Fi's receiver, Frost's light clock over heavier frost.
{
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
  niri msg action spawn -- dots-call lock lock
  until_ok 3000 locked_shown
}

# Pixels of a strip near r g b (tol $5, else 40), and the longest run of them, as "count run".
near_runs() {
  grim -s 1 -t ppm -g "$1" - | node -e '
    const b = require("fs").readFileSync(0), [r, g, bl, tol] = process.argv.slice(1).map(Number), want = [r, g, bl];
    const head = b.toString("latin1").match(/^P6\s+(\d+)\s+(\d+)\s+(\d+)\s/), px = b.subarray(head[0].length);
    let n = 0, run = 0, best = 0;
    for (let i = 0; i < head[1] * head[2]; i++) {
      if ([0, 1, 2].every((k) => Math.abs(px[i * 3 + k] - want[k]) <= tol)) { n++; run++; best = Math.max(best, run); } else run = 0;
    }
    console.log(n, best);
  ' "$2" "$3" "$4" "${5:-40}"
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
check "artboard: the lock draws its clock on a card, 96 px bold Maple Mono" state_is '.look == "card" and .clockFamily == "Maple Mono" and .clockPx == 96'
# The card is white and the paper grey, so a pixel inside the card's top-left reads white.
card_white() { local r g b; read -r r g b < <(grim -s 1 -t ppm -g "$(((ow - 460 + 1) / 2 + 24)),$((oh * 3 / 10 + 8)) 4x4" - | mean_rgb); ((r > 250 && g > 250 && b > 250)); }
until_ok 2000 card_white
check "artboard: the white card shows at the screen's centre" card_white
unlock

lock_in blueprint
check "blueprint: the clock's fill is transparent and its outline #7FE3F0 ($(lock_state | jq -c '[.clockFill, .clockStroke]'))" state_is '.look == "sheet" and .clockFill == "#00000000" and (.clockStroke | ascii_downcase) == "#7fe3f0"'
check "blueprint: the password field keeps its brackets" state_is '.fieldMarks == ["[", "]"]'
read -r cyan cyan_run < <(rows_runs 127 227 240)
read -r ground _ < <(rows_runs 12 26 46)
check "blueprint: rows across the clock have accent ($cyan px) and background ($ground px)" test "$cyan" -gt 10 -a "$ground" -gt 10
# A filled 200 px bold glyph crosses the row in runs of 20 px or more; an outline only in thin ones.
check "blueprint: the clock's strokes are thin outlines, not fills (longest accent run $cyan_run px)" test "$cyan_run" -le 8
unlock
check "blueprint: the test password unlocks" unlocked

lock_in hi-fi
check "hi-fi: the lock draws its receiver front, not Blueprint's sheet ($(lock_state | jq -r .look))" state_is '.look == "receiver"'
check "hi-fi: the password field has no brackets around it ($(lock_state | jq -c .fieldMarks))" state_is '.fieldMarks == []'
unlock
check "hi-fi: the test password unlocks" unlocked

# Frost's lock lays heavier frost over the whole screen, so each corner reads brighter than the desktop paper's under it.
box() { niri msg -j outputs | jq -r 'first(.[]).logical | "\(.x) \(.y) \(.width) \(.height)"'; }
# The 120 x 120 corner $1 (tl, tr, bl, br). The desktop's margins draw in the top 44 px, so the top corners start just below them.
corner() {
  local ox oy w h x y
  read -r ox oy w h < <(box)
  case $1 in tl | bl) x=$ox ;; *) x=$((ox + w - 120)) ;; esac
  case $1 in tl | tr) y=$((oy + 44)) ;; *) y=$((oy + h - 120)) ;; esac
  echo "$x,$y 120x120"
}
corner_rgb() { grim -s 1 -t ppm -g "$(corner "$1")" - | mean_rgb; }
# Exits 0 if each channel of the lock's corner $1 is at least 4 above the same channel of $2.
corner_brighter() { local a b; read -r -a a <<<"$(corner_rgb "$1")"; read -r -a b <<<"$2"; for i in 0 1 2; do ((a[i] - b[i] >= 4)) || return 1; done; }
failed_past() { state_is --argjson f "$1" '.failures > $f'; }

"$repo/bin/dots" theme frost >/dev/null
until_ok 2000 status_theme frost
# The 300 ms switch frost melts back to the paper's edges well within a second.
sleep 1
declare -A desk
for c in tl tr bl br; do desk[$c]=$(corner_rgb "$c"); done
niri msg action spawn -- dots-call lock lock
until_ok 3000 locked_shown
check "frost: the lock's clock is Inter Light at 168 px ($(lock_state | jq -c '[.look, .clockFamily, .clockPx, .clockWeight]'))" state_is '.look == "frost" and .clockFamily == "Inter" and .clockPx == 168 and .clockWeight == 300'
check "frost: the clock asks for #eceff4 ($(lock_state | jq -r .clockFill))" state_is '(.clockFill | ascii_downcase) == "#eceff4"'
# Ink #D8DEE9 sits within 20 of #ECEFF4, so only a tight tolerance tells the snow clock from an ink one.
read -r snow _ < <(rows_runs 236 239 244 8)
check "frost: rows across the clock hold $snow px within 8 of #ECEFF4" test "$snow" -gt 10
check "frost: the field is 380 px wide under 'Password for saiful' ($(lock_state | jq -c '[.fieldBox.w, .label]'))" state_is '.fieldBox.w == 380 and .label == "Password for saiful"'
host=$(tr -d '\n' </etc/hostname)
check "frost: the host name in muted #aeb7c6 sits above the clock ($(lock_state | jq -c '[.hostText, .hostColor]'))" state_is --arg h "$host" '.hostText == $h and (.hostColor | ascii_downcase) == "#aeb7c6" and .hostBox.y + .hostBox.h <= .clockBox.y'
check "frost: the date sits 14 px under the clock ($(lock_state | jq -c '.dateBox.y - (.clockBox.y + .clockBox.h)'))" state_is '.dateBox.y - (.clockBox.y + .clockBox.h) == 14'
check "frost: the bar reads Locked after a 14 px lock icon ($(lock_state | jq -c '[.statusText, .iconBox]'))" state_is '.statusText == "Locked" and .iconBox.w == 14 and .iconBox.x + .iconBox.w < .statusBox.x'
# The icon's 1.4 px strokes in muted cover a few whole pixels; the frost behind it stays at least 50 under muted.
read -r strokes _ < <(near_runs "$(lock_state | jq -r '.iconBox | "\(.x | floor),\(.y | floor) \(.w | ceil)x\(.h | ceil)"')" 174 183 198 40)
check "frost: the lock icon draws $strokes px near muted #AEB7C6" test "$strokes" -ge 4
check "frost: the bar's right reads the wifi and battery words in sentence case ('$(lock_state | jq -r .meter)')" state_is '(.meter | test("WIFI") | not) and (.meter | test("^((No )?Wi-Fi)?( ?[0-9]+%( charging)?)?$"))'
for c in tl tr bl br; do
  check "frost: the lock's $c corner ($(corner_rgb "$c")) is brighter than the desktop's (${desk[$c]}) by 4 or more" until_ok 3000 corner_brighter "$c" "${desk[$c]}"
done
before=$(lock_state | jq .failures)
wtype -- not-the-pass
wtype -k Return
check "frost: a wrong password counts as a failure" until_ok 3000 failed_past "$before"
check "frost: the lock stays up with its field empty ($(lock_state | jq -c '[.locked, .field]'))" state_is '.locked and .secure and .field == 0'
unlock
check "frost: the test password unlocks" unlocked

"$repo/bin/dots" theme paper >/dev/null
exit $((fails > 0))
}
