#!/usr/bin/env bash
# Five switches between artboard and catppuccin-mocha, with a foot running kak open, each end within 1000 ms of their start by the switch record's own stamps.
{
export DOTS_DEV_SCHEME=artboard
source "$(dirname "$0")/lib.sh"
unset TMUX

until_ok 5000 shell_status >/dev/null
niri msg action spawn -- foot -c /dev/null kak
kak_up() { local pid; pid=$(niri msg -j windows | jq -r '.[] | select(.app_id == "foot") | .pid'); [ -n "$pid" ] && pgrep -P "$pid" -x kak >/dev/null; }
until_ok 5000 kak_up
check "a foot running kak is open" kak_up
record=$XDG_STATE_HOME/dots/theme-switch.json
to=artboard
for i in 1 2 3 4 5; do
  [ "$to" = artboard ] && to=catppuccin-mocha || to=artboard
  "$repo/bin/dots" colorscheme "$to" >/dev/null
  rc=$?
  check "switch $i to $to exits 0 (got $rc)" test "$rc" = 0
  check "switch $i records its start and end, ${to}: $(jq -c . "$record")" jq -e --arg t "$to" '.to == $t and (.start | type) == "number" and (.end | type) == "number" and .end >= .start' "$record"
  check "switch $i ends within 1000 ms of its start ($(jq '.end - .start' "$record") ms)" jq -e '.end - .start <= 1000' "$record"
  until_ok 3000 eval "shell_status | jq -e '.theme == \"$to\" and .transition == \"\"' >/dev/null"
done

# Two switches at once take turns on the lock, and the desktop ends wholly in the one that ran last.
"$repo/bin/dots" colorscheme gruvbox-dark >/dev/null &
first=$!
"$repo/bin/dots" colorscheme rose-pine-dawn >/dev/null &
second=$!
wait "$first"
rc1=$?
wait "$second"
rc2=$?
check "two switches at once both exit 0 (got $rc1 and $rc2)" test "$rc1$rc2" = 00
last=$(<"$XDG_STATE_HOME/dots/theme")
check "the saved scheme is one of the two ($last)" eval '[ "$last" = gruvbox-dark ] || [ "$last" = rose-pine-dawn ]'
paper=$(sed -n 's/^paper = "\(#[0-9A-F]*\)"$/\1/p' "$repo/colorschemes/$last.toml")
check "the shell tokens name $last" jq -e --arg t "$last" '.name == $t' "$XDG_STATE_HOME/dots/theme-out/shell.json"
check "niri's paper is $last's $paper" grep -q "background-color \"$paper\"" "$XDG_STATE_HOME/dots/theme-out/niri.kdl"
until_ok 3000 eval "shell_status | jq -e '.theme == \"$last\" and .transition == \"\"' >/dev/null"
check "the shell ends in $last" eval "shell_status | jq -e '.theme == \"$last\"' >/dev/null"

exit $((fails > 0))
}
