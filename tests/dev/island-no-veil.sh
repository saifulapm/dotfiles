#!/usr/bin/env bash
# Nothing in the shell is a card any more: opening each keyed surface draws no veil, so the pixel 10 px in from the output's bottom left corner never changes, and the shell keeps one dots-surfaces Overlay window (NZ4Z0ZF2, XKQ911PH). The Recorder's dim is its board's region overlay, not a veil, so it is left out.
{
source "$(dirname "$0")/lib.sh"

island() { timeout 0.5 qs ipc call island state 2>/dev/null; }
island_is() { island | jq -e "$@" >/dev/null 2>&1; }
at_rest() { island_is '.surface == null and .takeover == null and .animating == false'; }
px() { grim -g "$1,$2 1x1" -t ppm - 2>/dev/null | tail -c3 | od -An -tx1 | tr -d ' \n'; }

until_ok 5000 shell_status >/dev/null
read -r oh < <(niri msg -j outputs | jq -r '.[] | .logical.height')
until_ok 5000 at_rest
corner=$(px 10 $((oh - 10)))

for s in launcher notifs cheatsheet control pass tailscale accounts dns goals; do
  niri msg action spawn -- dots-call "$s" toggle
  until_ok 3000 island_is --arg s "$s" '.surface == $s and .animating == false'
  check "with $s open the corner pixel is as it was, no veil ($(px 10 $((oh - 10))), was $corner)" test "$(px 10 $((oh - 10)))" = "$corner"
  niri msg action spawn -- dots-call "$s" toggle
  until_ok 3000 at_rest
done

check "niri lists one dots-surfaces window, on the Overlay layer ($(niri msg -j layers | jq -c '[.[] | select(.namespace == "dots-surfaces") | .layer]'))" \
  bash -c 'niri msg -j layers | jq -e "[.[] | select(.namespace == \"dots-surfaces\") | .layer] == [\"Overlay\"]" >/dev/null'

exit $((fails > 0))
}
