#!/usr/bin/env bash
# The margins and the island, from niri's event stream and the shell's one minute tick.
{
source "$(dirname "$0")/lib.sh"

until_ok 5000 shell_status >/dev/null
margins() { timeout 0.5 qs ipc call margins state 2>/dev/null; }
island() { timeout 0.5 qs ipc call island state 2>/dev/null; }

# The desk where the strip and the old rule were, before any window opens; it is the field, so each later read is held to it.
desk_strip=$(grim -s 1 -t ppm -g "40,44 10x10" - | mean_rgb)
desk_rule=$(grim -s 1 -t ppm -g "200,39 10x3" - | mean_rgb)
niri msg action spawn -- foot -c /dev/null
foot_focused() { niri msg -j windows | jq -e 'any(.[]; .app_id == "foot" and .is_focused)' >/dev/null; }
until_ok 5000 foot_focused
check "foot is focused" foot_focused
# The same spot's desk as read before foot opened: within 3 per channel.
is_desk() { local r g b R G B; read -r r g b <<<"$1"; read -r R G B <<<"$2"; ((r - R <= 3 && R - r <= 3 && g - G <= 3 && G - g <= 3 && b - B <= 3 && B - b <= 3)); }
# Between the margins' text and the window top at y=56 there is only the desk.
strip=$(grim -s 1 -t ppm -g "40,44 10x10" - | mean_rgb)
echo "     margin strip with foot open: $strip"
check "foot opens below the margins" is_desk "$strip" "$desk_strip"
# The margins are text alone: no rule runs under them at y=40, where the ink one was.
rule=$(grim -s 1 -t ppm -g "200,39 10x3" - | mean_rgb)
check "no rule runs under the margins ($rule)" is_desk "$rule" "$desk_rule"
# niri animates a window open, so the edge is polled until the window has settled. The focused window's only frame is a 1 px edge in the dots' line #D0D7DE at x=32, the left strut, with foot's own grey 36 36 36 right after.
edge_is_line() { local r g b; edge=$(grim -s 1 -t ppm -g "32,300 1x10" - | mean_rgb); read -r r g b <<<"$edge"; ((r >= 200 && r <= 216 && g >= 207 && g <= 223 && b >= 214 && b <= 230)); }
inside_is_foot() { local r g b; inside=$(grim -s 1 -t ppm -g "33,300 1x10" - | mean_rgb); read -r r g b <<<"$inside"; ((r >= 30 && r <= 42 && g >= 30 && g <= 42 && b >= 30 && b <= 42)); }
until_ok 1000 edge_is_line
check "niri edges the focused foot in the dots' line at x=32 ($edge)" edge_is_line
until_ok 1000 inside_is_foot
check "and foot's own grey starts right inside it ($inside)" inside_is_foot

# Maximized to edges, foot fills the whole output and the margins and the island hide, as for a fullscreen window.
niri msg action maximize-window-to-edges
out_h=$(niri msg -j outputs | jq '.[].logical.height' | head -n1)
fills() { [ "$(niri msg -j focused-window | jq '.layout.tile_size[1] | floor')" = "$out_h" ]; }
until_ok 1000 fills
check "a window maximized to edges is $out_h px tall" fills
bar_hidden() { margins | jq -e '.shown == false' >/dev/null 2>&1 && island | jq -e '.shown == false' >/dev/null 2>&1; }
until_ok 1000 bar_hidden
check "the margins and the island hide over it" bar_hidden
# foot's own background, not the paper, now sits under the margins.
strip=$(grim -s 1 -t ppm -g "40,30 10x10" - | mean_rgb)
check "foot covers the margin strip ($strip)" eval '! is_paper "$strip"'
niri msg action maximize-window-to-edges
bar_back() { margins | jq -e '.shown == true' >/dev/null 2>&1 && island | jq -e '.shown == true' >/dev/null 2>&1; }
until_ok 1000 bar_back
check "the margins and the island come back once it is unmaximized" bar_back

# foot's shell retitles the window once it starts, so the title is read again on every poll.
left_is_foot() {
  title=$(niri msg -j focused-window | jq -r .title)
  margins | jq -e --arg t "$title" '.left.text == "01 · foot — " + $t' >/dev/null 2>&1
}
until_ok 1000 left_is_foot
echo "     margins: $(margins)"
check "the top-left reads 01 · foot — <foot's title>" left_is_foot

niri msg action focus-workspace 2
start=$(now_ms)
reads_02() { margins | jq -e '.left.text == "02"' >/dev/null 2>&1; }
# No sleep between reads, so the poll adds no delay of its own.
until reads_02; do (($(now_ms) - start < 2000)) || break; done
elapsed=$(($(now_ms) - start))
check "the top-left reads 02 ${elapsed} ms after focus-workspace 2" test "$elapsed" -le 100

island_is_now() {
  local text now
  text=$(island | jq -r .text 2>/dev/null)
  now=$(date +%H:%M)
  echo "     island: $text, date: $now"
  [ "$text" = "$now" ]
}
# The minute can roll over between the two reads, so one mismatch earns one re-read.
island_now_or_next() { island_is_now || island_is_now; }
check "the island shows date +%H:%M" island_now_or_next
at_rest() { island | jq -e '.mode == "rest" and .width > 0 and .width <= 560' >/dev/null; }
check "the island state reports rest and a width within 560 px" at_rest

status=$(shell_status)
echo "     status: $status"
one_timer() { jq -e '.timers == 1' <<<"$status" >/dev/null; }
check "status reports one running timer" one_timer

layers=$(niri msg -j layers)
on_top() { jq -e --arg ns "$1" 'any(.[]; .namespace == $ns and .layer == "Top")' <<<"$layers" >/dev/null; }
check "dots-margins is on the Top layer" on_top dots-margins
check "dots-island is on the Top layer" on_top dots-island

# A visible that reads the window's own screen runs again while Quickshell sets that screen, and qs logs a binding loop.
loops() { journalctl --user -u "$DOTS_DEV_UNIT" --no-pager -o cat | grep -A1 'Binding loop detected for property "visible"' | grep -o '[A-Za-z]*\.qml:[0-9]*' | sort -u | paste -sd' '; }
check "no margin or island visible loops on its screen ($(loops))" test -z "$(loops)"

exit $((fails > 0))
}
