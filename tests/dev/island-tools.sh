#!/usr/bin/env bash
# Pass, Tailscale, Accounts, Goals and DNS Shield grow the island to their own width (board 8: 640 px, DNS 880 px), a click on one stays in it, Esc gives it back, one key morphs straight to another, and Pass unloads 30 s after its close and opens again cold.
{
source "$(dirname "$0")/lib.sh"
source "$(dirname "$0")/pointer.bash"

island() { timeout 0.5 qs ipc call island state 2>/dev/null; }
island_is() { island | jq -e "$@" >/dev/null 2>&1; }
tool() { timeout 0.5 qs ipc call "$1" state 2>/dev/null; }
tool_is() {
  local s=$1
  shift
  tool "$s" | jq -e "$@" >/dev/null 2>&1
}
at_rest() { island_is '.surface == null and .animating == false'; }
key() {
  wtype -k "$1"
  sleep 0.15
}
open_tool() {
  niri msg action spawn -- dots-call "$1" toggle
  until_ok 3000 island_is --arg s "$1" '.surface == $s and .animating == false'
  until_ok 2000 tool_is "$1" '.keyboard and .settled'
}

read -r ow _ < <(niri msg -j outputs | jq -r '.[] | .logical | "\(.width) \(.height)"')
until_ok 5000 at_rest

for pair in pass:640 tailscale:640 accounts:640 goals:640 dns:880; do
  s=${pair%%:*} w=${pair#*:}
  want=$((ow - 48 < w ? ow - 48 : w))
  open_tool "$s"
  check "the $s key sets surface to $s and the island $want px wide ($(island | jq -c '{surface, width}'))" island_is --arg s "$s" --argjson w "$want" '.surface == $s and .width == $w'
  # A press on the tool's heading, inside the island but on no row, is a press on the tool, not one outside it.
  point click $(((ow - want) / 2 + 30)) 26
  sleep 0.3
  check "a click on $s's heading keeps $s open ($(tool "$s" | jq -c '{open}'))" tool_is "$s" '.open'
  until_ok 2000 tool_is "$s" '.keyboard and .settled'
  key Escape
  until_ok 3000 at_rest
  check "Esc closes $s and the island comes to rest ($(island | jq -c '{surface, animating}'))" tool_is "$s" '.open == false'
done

# One tool's key while another shows morphs straight to it, never through rest.
open_tool pass
niri msg action spawn -- dots-call tailscale toggle
until_ok 3000 island_is '.surface == "tailscale" and .animating == false'
check "Mod+T while Pass shows morphs the island to Tailscale and closes Pass ($(tool pass | jq -c '{open}'))" tool_is pass '.open == false'
until_ok 2000 tool_is tailscale '.keyboard and .settled'
key Escape
until_ok 3000 at_rest

# Pass, drawn in the island and the island's last surface after its close, still unloads 30 s after it.
check "Pass unloads within 35 s of its close" until_ok 35000 tool_is pass '.loaded == false'
open_tool pass
check "Pass opens again after its unload, timed cold ($(tool pass | jq -c '{open, openMs}'))" tool_is pass '.open and (.openMs | type) == "number"'
key Escape
until_ok 3000 at_rest

exit $((fails > 0))
}
