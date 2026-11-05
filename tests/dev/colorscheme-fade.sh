#!/usr/bin/env bash
# A colorscheme switch plays one 260 ms crossfade: the shell's own stamps read 240 to 280 ms for five switches between catppuccin-mocha and rose-pine-dawn, and every ordered pair of the five schemes names fade; colorscheme-fade-slow.sh shoots its middle.
{
export DOTS_DEV_SCHEME=catppuccin-mocha
source "$(dirname "$0")/lib.sh"
unset TMUX

rest_in() { shell_status | jq -e --arg t "$1" '.theme == $t and .transition == ""' >/dev/null; }
until_ok 5000 rest_in catppuccin-mocha

# Timed by the shell's own stamps, with nothing polling inside the timed window (lessons 2026-11-01, 2026-11-04).
to=catppuccin-mocha
for i in 1 2 3 4 5; do
  [ "$to" = rose-pine-dawn ] && to=catppuccin-mocha || to=rose-pine-dawn
  "$repo/bin/dots" colorscheme "$to" >/dev/null
  sleep 0.6
  until_ok 3000 rest_in "$to"
  ms=$(shell_status | jq '.transitionEndedAt - .transitionStartedAt')
  check "switch $i to $to crossfades for 240 to 280 ms by the shell's stamps ($ms ms)" test "$ms" -ge 240 -a "$ms" -le 280
done

# Every ordered pair once: for each step k, five hops of +k round the five schemes come back to the start.
schemes=(artboard catppuccin-mocha github-light gruvbox-dark rose-pine-dawn)
"$repo/bin/dots" colorscheme artboard >/dev/null
until_ok 3000 rest_in artboard
at=0 kinds=()
for k in 1 2 3 4; do
  for _ in 1 2 3 4 5; do
    next=$(((at + k) % 5))
    "$repo/bin/dots" colorscheme "${schemes[next]}" >/dev/null &
    pid=$!
    kind=""
    for _ in $(seq 60); do
      kind=$(shell_status | jq -r '.transition // ""')
      [ -n "$kind" ] && break
    done
    wait "$pid"
    kinds+=("${schemes[at]}>${schemes[next]}:${kind:-none}")
    until_ok 3000 rest_in "${schemes[next]}"
    at=$next
  done
done
bad=$(printf '%s\n' "${kinds[@]}" | grep -v ':fade$')
check "all 20 ordered pairs of the five schemes switch by fade (${#kinds[@]} seen${bad:+; not fade: $bad})" test "${#kinds[@]}" = 20 -a -z "$bad"

exit $((fails > 0))
}
