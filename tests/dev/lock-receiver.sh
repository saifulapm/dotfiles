#!/usr/bin/env bash
# Hi-Fi locks into a receiver's front panel: walnut cheeks, the machine's name over a glass dial with an amber clock, and a password well.
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

# The share of a region's pixels within a tolerance of r g b on every channel, in percent.
near_share() {
  grim -s 1 -t ppm -g "$1" - | node -e '
    const b = require("fs").readFileSync(0), [tol, ...want] = process.argv.slice(1).map(Number);
    const head = b.toString("latin1").match(/^P6\s+(\d+)\s+(\d+)\s+(\d+)\s/), px = b.subarray(head[0].length);
    const n = head[1] * head[2];
    let near = 0;
    for (let i = 0; i < n; i++) if ([0, 1, 2].every((k) => Math.abs(px[i * 3 + k] - want[k]) <= tol)) near++;
    console.log(Math.round((near * 100) / n));
  ' "$2" "$3" "$4" "$5"
}
box() { lock_state | jq -r --arg k "$1" '.[$k] | "\(.x | floor) \(.y | floor) \(.w | floor) \(.h | floor)"'; }

until_ok 5000 shell_status >/dev/null
read -r ow oh < <(niri msg -j outputs | jq -r 'first(.[]).logical | "\(.width) \(.height)"')
host=$(tr '[:lower:]' '[:upper:]' </etc/hostname)

lock_in hi-fi
check "hi-fi: the lock draws the receiver front ($(lock_state | jq -r .look))" state_is '.look == "receiver"'
check "hi-fi: the host line names this machine, $host ($(lock_state | jq -r .host))" state_is --arg h "$host · STEREO RECEIVER" '.host == $h'

# The grain lines differ from the walnut, so most of each cheek, not all of it, reads #3A2A1F.
left=$(near_share "0,$((oh / 4)) 32x$((oh / 2))" 12 58 42 31)
right=$(near_share "$((ow - 32)),$((oh / 4)) 32x$((oh / 2))" 12 58 42 31)
check "hi-fi: the left cheek is walnut ($left% within 12 of #3A2A1F)" test "$left" -ge 60
check "hi-fi: the right cheek is walnut ($right% within 12 of #3A2A1F)" test "$right" -ge 60

read -r dx dy dw dh < <(box dialBox)
check "hi-fi: the dial window is 960 x 320 (${dw} x ${dh})" test "$dw" -eq 960 -a "$dh" -eq 320
glass=$(near_share "$((dx + 10)),$((dy + dh - 14)) 8x8" 6 20 22 23)
check "hi-fi: the dial's empty corner is glass #141617 ($glass%)" test "$glass" -ge 90
read -r cx cy cw ch < <(box clockBox)
check "hi-fi: the clock sits inside the dial" test "$cx" -ge "$dx" -a "$((cy + ch))" -le "$((dy + dh))"
amber=$(near_share "$cx,$((cy + ch / 3)) ${cw}x$((ch / 3))" 40 250 189 47)
check "hi-fi: the clock is lit amber ($amber% of its middle third near #FABD2F)" test "$amber" -ge 5

failed() { state_is '.failures >= 1'; }
wtype -- wrong-pass
wtype -k Return
until_ok 3000 failed
check "hi-fi: a wrong password leaves the lock locked" locked_shown
unlock
check "hi-fi: the test password unlocks" unlocked

"$repo/bin/dots" theme paper >/dev/null
exit $((fails > 0))
}
