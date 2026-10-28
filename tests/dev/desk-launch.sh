#!/usr/bin/env bash
# screen launch makes agent windows: what opens within 5 s of a launch, or of an agent action in an agent window, joins; what opens 6 s on does not; a footclient window joins though its pid is the server's; the set is this niri's alone.
{
source "$(dirname "$0")/lib.sh"

scripts=$repo/home/dot_claude/skills/desktop/scripts
agent() { "$scripts/desk" window "$1" | jq -r .agent; }
ids() { niri msg -j windows | jq -r "[.[] | select(.app_id == \"$1\") | .id] | sort | .[]"; }
newest() { ids "$1" | tail -1; }
count_is() { [ "$(ids "$1" | wc -l)" = "$2" ]; }

# A foot open before the first launch is never an agent window.
niri msg action spawn -- foot -c /dev/null
until_ok 5000 count_is foot 1
mine=$(newest foot)

out=$("$scripts/screen" launch gtk4-widget-factory)
check "screen launch prints what it started" bash -c "jq -e '.launched == [\"gtk4-widget-factory\"]' <<<'$out' >/dev/null"
until_ok 8000 count_is org.gtk.WidgetFactory4 1
factory=$(newest org.gtk.WidgetFactory4)
check "the widget factory it launched is an agent window" test "$(agent "$factory")" = true
check "and the foot opened before it is not" test "$(agent "$mine")" = false

# 6 s after the launch, a window opens without one.
sleep 6
niri msg action spawn -- foot -c /dev/null
until_ok 5000 count_is foot 2
late=$(newest foot)
check "a foot opening 6 s after the launch is not an agent window" test "$(agent "$late")" = false

# An agent action in an agent window opens a 5 s window of its own; one in a window of Saiful's does not.
"$scripts/desk" acted "$late"
niri msg action spawn -- foot -c /dev/null
until_ok 5000 count_is foot 3
after_his=$(newest foot)
check "an action noted in a window not the agent's lets nothing join" test "$(agent "$after_his")" = false
"$scripts/desk" acted "$factory"
niri msg action spawn -- foot -c /dev/null
until_ok 5000 count_is foot 4
after_ours=$(newest foot)
check "a window opening just after an action in the factory joins" test "$(agent "$after_ours")" = true

# footclient's window belongs to the foot server's pid, which an agent did not start.
niri msg action spawn -- foot --server -c /dev/null
sleep 6
"$scripts/screen" launch footclient
until_ok 5000 count_is footclient 1
client=$(newest footclient)
server=$(niri msg -j windows | jq ".[] | select(.id == $client) | .pid")
check "a footclient launched with the server running is an agent window" test "$(agent "$client")" = true
check "though its pid ($server) is the server's, not one the launch started" bash -c "tr '\0' ' ' </proc/$server/cmdline | grep -q -- '--server'"

# The set is keyed by this niri's socket, so the live desktop's never holds these windows.
dir=$XDG_RUNTIME_DIR/desk/$(basename "$NIRI_SOCKET")
check "the state dir is named by the nested NIRI_SOCKET ($(basename "$NIRI_SOCKET"))" test -f "$dir/windows.json"
live=$(ls -d "$XDG_RUNTIME_DIR"/desk/niri.wayland-1.* 2>/dev/null | head -1)
check "and is not the live niri's" test "$dir" != "$live"
check "whose list, if it has one, holds none of these windows" bash -c "[ -z '$live' ] || ! jq -e 'has(\"$factory\") and .[\"$factory\"].app_id == \"org.gtk.WidgetFactory4\"' '$live/windows.json' >/dev/null 2>&1"
# A window that closes leaves the set.
niri msg action close-window --id "$factory"
gone() { ! jq -e "has(\"$factory\")" "$dir/windows.json" >/dev/null; }
check "a closed agent window leaves the set" until_ok 3000 gone

exit $((fails > 0))
}
