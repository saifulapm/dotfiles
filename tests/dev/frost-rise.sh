#!/usr/bin/env bash
# Frost's launcher fades its glass in over 160 ms ease-out with the blur behind it from the first frame, and its content rises 4 px; Esc closes it in 128 ms. A second run slowed 20 times sees the content mid-rise while the card stays at rest.
{
# The slowdown is read as the nested shell starts, so the slowed run gets its own session, before this one takes the lock.
slow_rc=0
if [ -z "${DOTS_MOTION_SLOWDOWN:-}" ]; then
  DOTS_MOTION_SLOWDOWN=20 bash "$0"
  slow_rc=$?
fi
source "$(dirname "$0")/lib.sh"

launcher_state() { timeout 0.5 qs ipc call launcher state 2>/dev/null; }
state_is() { launcher_state | jq -e "$1" >/dev/null; }
blur_is() { timeout 0.5 qs ipc call shell blur 2>/dev/null | jq -e "$1" >/dev/null; }
status_theme() { shell_status | jq -e --arg t "$1" '.theme == $t and .transition == ""' >/dev/null; }
in_theme() { "$repo/bin/dots" theme "$1" >/dev/null; until_ok 3000 status_theme "$1"; }
press() { t0=$(now_ms); niri msg action spawn -- dots-call launcher toggle >/dev/null; }

until_ok 5000 shell_status >/dev/null
in_theme frost

if [ -n "${DOTS_MOTION_SLOWDOWN:-}" ]; then
  # 400 ms into the 3.2 s open the ease-out has the content about 2.7 px below its rest; the one state read is the only call in the window.
  press
  while (($(now_ms) - t0 < 400)); do sleep 0.005; done
  mid=$(launcher_state)
  until_ok 8000 state_is '.open and .settled'
  rest=$(launcher_state)
  echo "     mid-open field y $(jq .fieldBox.y <<<"$mid") card $(jq -c .cardBox <<<"$mid"); at rest field y $(jq .fieldBox.y <<<"$rest") card $(jq -c .cardBox <<<"$rest")"
  mid_is() { jq -en --argjson m "$mid" --argjson r "$rest" "$1" >/dev/null; }
  check "slowed: mid-open the launcher is still opening" mid_is '$m.open and ($m.settled | not)'
  check "slowed: mid-open the content is drawn between 0 and 4 px below its rest" mid_is '($m.fieldBox.y - $r.fieldBox.y) as $d | $d > 0 and $d < 4'
  check "slowed: mid-open the card's drawn box is at rest" mid_is '[$m.cardBox.x - $r.cardBox.x, $m.cardBox.y - $r.cardBox.y, $m.cardBox.w - $r.cardBox.w, $m.cardBox.h - $r.cardBox.h] | map(fabs < 0.5) | all'
  wtype -k Escape
  until_ok 6000 state_is '.open == false and .drawing == false'
else
  press
  until_ok 3000 state_is '.open and .keyboard and .settled'
  check "frost: the launcher reports an open of 160 ms ease-out, a close of 128 ms and a 4 px rise ($(launcher_state | jq -c '[.motion, .motionMs, .curve, .rise]'))" \
    state_is '.motion == "fade" and .motionMs == {"open": 160, "close": 128} and .curve == "ease-out" and .rise == 4'
  check "frost: the blur region on the open's first frame is non-empty and the one at rest ($(launcher_state | jq -c '[.firstRegion, .blurRegion]'))" \
    state_is '(.firstRegion | length) == 1 and .firstRegion[0].w > 0 and .firstRegion[0].h > 0 and .firstRegion == .blurRegion'
  wtype -k Escape
  until_ok 2000 state_is '.open == false and .drawing == false'
  check "frost: the close after Esc took 120 to 160 ms ($(launcher_state | jq .closeTookMs) ms)" state_is '.closeTookMs >= 120 and .closeTookMs <= 160'
  check "frost: closed, the launcher asks for no blur region" state_is '.blurRegion == []'
  check "frost: closed, the Surfaces window asks niri for no region" blur_is '.surfaces == 0'
fi

errors=$(qml_errors)
[ -n "$errors" ] && echo "$errors"
check "the shell's journal has no QML error" test -z "$errors"

exit $((fails > 0 || slow_rc != 0))
}
