#!/usr/bin/env bash
# Mod+Escape locks, only the test password unlocks, and a shell killed while locked locks again on restart.
source "$(dirname "$0")/lib.sh"

marker=$XDG_STATE_HOME/dots/locked
# A killed instance's socket lingers, so every call goes to the unit's current process.
shell_pid() { systemctl --user show -p MainPID --value "$DOTS_DEV_UNIT"; }
# The pid picks the instance, and qs refuses a config path beside it.
lock_state() { timeout 0.5 env -u QS_CONFIG_PATH qs ipc --pid "$(shell_pid)" call lock state 2>/dev/null; }
state_is() { lock_state | jq -e "$1" >/dev/null 2>&1; }
# niri runs no binds for wtype's virtual keyboard, so the check spawns the bind's command through niri.
mod_escape() { niri msg action spawn -- qs ipc call lock lock; }
# Dark pixels in the band where the lock draws its clock: the paper alone has none.
clock_ink() {
  local geo
  geo=$(niri msg -j outputs | jq -r 'first(.[]).logical | "\(.x + (.width / 4 | floor)),\(.y + (.height / 5 | floor)) \(.width / 2 | floor)x\(.height * 3 / 10 | floor)"')
  grim -s 1 -t ppm -g "$geo" - | node -e '
    const b = require("fs").readFileSync(0);
    const head = b.toString("latin1").match(/^P6\s+(\d+)\s+(\d+)\s+(\d+)\s/);
    const px = b.subarray(head[0].length);
    let n = 0;
    for (let i = 0; i < head[1] * head[2] * 3; i += 3) if (px[i] < 80 && px[i + 1] < 80 && px[i + 2] < 80) n++;
    console.log(n);
  '
}
locked_shown() { state_is '.locked and .secure'; }
type_enter() { wtype -- "$1"; wtype -k Return; }

until_ok 5000 shell_status >/dev/null
check "unlocked at start" state_is '.locked == false'
ink_before=$(clock_ink)

mod_escape
until_ok 3000 locked_shown
check "Mod+Escape locks and niri confirms the lock" locked_shown
ink_after=$(clock_ink)
check "the screen shows the clock ($ink_before dark px before, $ink_after after)" test "$ink_after" -gt $((ink_before + 500))
check "the lock marker is written" test -e "$marker"

wtype -- wrong-pass
until_ok 2000 state_is '.field == 10'
check "typing reaches the password field" state_is '.field == 10'
wtype -k Return
until_ok 1000 state_is '.shaking'
check "a wrong password shakes the field" state_is '.shaking'
until_ok 3000 state_is '.failures == 1'
check "a wrong password leaves it locked with the field empty" state_is '.locked and .secure and .field == 0 and .failures == 1'

until_ok 2000 state_is '.shaking == false'
wtype -k Return
until_ok 1000 state_is '.shaking'
check "Enter on an empty field shakes it" state_is '.shaking'
check "Enter on an empty field leaves it locked" state_is '.locked and .secure and .field == 0'

type_enter dots-test-pass
until_ok 3000 state_is '.locked == false'
check "the test password unlocks" state_is '.locked == false and .field == 0'
until_ok 1000 test ! -e "$marker"
check "unlocking removes the marker" test ! -e "$marker"

# A magenta window behind the lock: any magenta on screen while the shell is dead means niri showed the desktop.
magenta() {
  grim -s 1 -t ppm - | node -e '
    const b = require("fs").readFileSync(0);
    const head = b.toString("latin1").match(/^P6\s+(\d+)\s+(\d+)\s+(\d+)\s/);
    const px = b.subarray(head[0].length);
    let n = 0;
    for (let i = 0; i < head[1] * head[2] * 3; i += 3) if (px[i] > 200 && px[i + 1] < 60 && px[i + 2] > 200) n++;
    console.log(n);
  '
}
niri msg action spawn -- foot -o colors.background=ff00ff -e sleep 120
magenta_shown() { (($(magenta) > 10000)); }
until_ok 5000 magenta_shown
check "a magenta window shows before the lock" magenta_shown

mod_escape
until_ok 3000 locked_shown
check "Mod+Escape locks again" locked_shown
old=$(shell_pid)
t0=$(now_ms)
systemctl --user kill -s KILL "$DOTS_DEV_UNIT"
# The unit restarts after 500 ms, so grabs in that gap show what niri draws with no lock client.
seen=0 grabs=0
while [ "$(shell_pid)" = "$old" ] || [ -z "$(shell_pid)" ] || [ "$(shell_pid)" = 0 ]; do
  (($(now_ms) - t0 < 2000)) || break
  seen=$((seen + $(magenta))) grabs=$((grabs + 1))
done
check "while the shell is dead the screen stays covered ($grabs grabs, $seen magenta px)" test "$grabs" -gt 0 -a "$seen" = 0
restarted_locked() { [ "$(shell_pid)" != "$old" ] && locked_shown; }
until_ok 2000 restarted_locked
took=$(($(now_ms) - t0))
check "the restarted shell holds the lock within 2 s of the kill (${took} ms)" restarted_locked
lock_drawn() { (($(clock_ink) > 0)) && (($(magenta) == 0)); }
until_ok 2000 lock_drawn
check "the restarted shell draws its lock over the magenta window" lock_drawn
check "the marker survives the kill" test -e "$marker"

type_enter dots-test-pass
until_ok 3000 state_is '.locked == false'
check "the test password unlocks the restarted shell" state_is '.locked == false'

# With no dots-lock service the lock falls back to login, since PAM's other service would refuse every password.
mv "$DOTS_PAM_DIR/dots-lock" "$DOTS_PAM_DIR/login"
old=$(shell_pid)
systemctl --user restart "$DOTS_DEV_UNIT"
until_ok 5000 bash -c "[ \"\$(systemctl --user show -p MainPID --value $DOTS_DEV_UNIT)\" != $old ]"
until_ok 5000 state_is '.locked == false'
mod_escape
until_ok 3000 locked_shown
type_enter wrong-password
until_ok 3000 state_is '.failures >= 1'
check "without dots-lock, a wrong password still leaves it locked" state_is '.locked and .failures >= 1'
type_enter dots-test-pass
until_ok 3000 state_is '.locked == false'
check "without dots-lock, the password unlocks through login" state_is '.locked == false'

exit $((fails > 0))
