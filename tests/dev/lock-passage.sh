#!/usr/bin/env bash
# The lock draws the day's other passage, walked back from the paper's, between its clock and its field on the bare ground, read through lock state and passage state.
{
work=$(mktemp -d)
source "$(dirname "$0")/lib-deen-bangla.sh"
export DOTS_DEV_DEEN=$work/deen-bangla
source "$(dirname "$0")/lib.sh"
cleanup() { rm -rf "$work"; }

lock_state() { timeout 0.5 dots-call lock state 2>/dev/null; }
lock_is() { lock_state | jq -e "$@" >/dev/null 2>&1; }
paper() { timeout 0.5 dots-call passage state 2>/dev/null; }
height=$(niri msg -j outputs | jq 'first(.[]).logical.height')

until_ok 5000 shell_status >/dev/null
until_ok 5000 sh -c 'timeout 0.5 dots-call passage state | jq -e ".bn != \"\" or .en != \"\"" >/dev/null'
niri msg action spawn -- dots-call lock lock
until_ok 5000 lock_is '.locked and .secure and .passage.box != null'
check "the lock draws a passage ($(lock_state | jq -c .passage))" lock_is '.passage.box != null'
check "it is not the paper's kind: the lock's $(lock_state | jq -r .passage.kind), the paper's $(paper | jq -r .kind)" \
  lock_is --arg k "$(paper | jq -r .kind)" '$k != "" and .passage.kind != $k'
check "it sits between the date and the field ($(lock_state | jq -c '[.dateBox, .passage.box, .fieldBox]'))" \
  lock_is '.dateBox.y + .dateBox.h < .passage.box.y and .passage.box.y + .passage.box.h < .fieldBox.y'
check "the clock stands in the screen's second fifth, below the top ($(lock_state | jq -c .clockBox), height $height)" \
  lock_is --argjson h "$height" '.clockBox.y >= $h * 0.2 and .clockBox.y < $h * 0.4'
check "the field sits low, under the screen's middle ($(lock_state | jq -c .fieldBox))" \
  lock_is --argjson h "$height" '.fieldBox.y > $h * 0.7'

wtype -- dots-test-pass
wtype -k Return
until_ok 3000 lock_is '.locked == false'
check "the test password still unlocks" lock_is '.locked == false'

exit $((fails > 0))
}
