#!/usr/bin/env bash
# The island morphs by the theme's motion: Artboard's spring overshoots and settles, Paper's snappy curve never does, and nothing runs at rest.
{
export DOTS_DEV_THEME=artboard
source "$(dirname "$0")/lib.sh"

until_ok 5000 shell_status >/dev/null
island() { timeout 0.5 qs ipc call island state 2>/dev/null; }
mode_is() { island | jq -e --arg m "$1" '.mode == $m' >/dev/null 2>&1; }
settled() { island | jq -e '.animating == false' >/dev/null 2>&1; }

# Samples the drawn width until the island stops moving; prints the widest sample and the ms from the mode change to the last moving sample.
watch_morph() {
  local s widest=0 last=0 since
  while s=$(island) && [ -n "$s" ]; do
    since=$(jq .since <<<"$s")
    widest=$(jq --argjson w "$widest" '[.drawn, $w] | max' <<<"$s")
    jq -e .animating <<<"$s" >/dev/null || break
    last=$(($(now_ms) - since))
  done
  echo "$widest $last"
}

until_ok 3000 settled
notify-send "morph"
until_ok 2000 mode_is notification
read -r widest took < <(watch_morph)
echo "     artboard open: widest ${widest} px, moving for ${took} ms"
check "Artboard's spring overshoots the 440 px card (${widest} px)" eval "(( \$(printf %.0f $widest) > 440 ))"
check "and settles within 800 ms (${took} ms)" test "$took" -le 800
check "at exactly 440 px" eval 'island | jq -e ".drawn == 440 and .width == 440" >/dev/null'

until_ok 7000 mode_is rest
read -r _ took < <(watch_morph)
check "closing back to the clock settles faster than opening (${took} ms)" test "$took" -le 600
check "at the clock's own width" eval 'island | jq -e ".drawn == .width and .width < 100" >/dev/null'

"$repo/bin/dots" theme paper >/dev/null
until_ok 3000 settled
notify-send "snap"
until_ok 2000 mode_is notification
read -r widest took < <(watch_morph)
echo "     paper open: widest ${widest} px, moving for ${took} ms"
check "Paper's snappy curve never passes 440 px (${widest} px)" eval "(( \$(printf %.0f $widest) <= 440 ))"
check "and settles within 250 ms (${took} ms)" test "$took" -le 250

exit $((fails > 0))
}
