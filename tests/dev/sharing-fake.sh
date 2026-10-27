#!/usr/bin/env bash
# PipeWire shares, which a nested niri cannot make, come from the relay: LIVE names a window's app, counts two, and says NOTHING or PAUSED.
{
export DOTS_DEV_FAKE_CASTS=1
source "$(dirname "$0")/lib.sh"

island() { timeout 0.5 qs ipc call island state 2>/dev/null; }
island_text() { island | jq -r .text; }
reads() { [ "$(island_text)" = "$1" ]; }
mode_is() { island | jq -e --arg m "$1" '.mode == $m' >/dev/null; }
# cast <stream> <session> <target json> [active]: a PipeWire cast as niri reports one a portal started.
cast() { fake_event "{\"CastStartedOrChanged\":{\"cast\":{\"stream_id\":$1,\"session_id\":$2,\"kind\":\"PipeWire\",\"target\":$3,\"is_dynamic_target\":true,\"is_active\":${4:-true},\"pid\":null,\"pw_node_id\":$((40 + $1))}}}" >/dev/null; }
uncast() { fake_event "{\"CastStopped\":{\"stream_id\":$1}}" >/dev/null; }
window_of() { niri msg -j windows | jq -e --arg a "$1" 'first(.[] | select(.app_id == $a)) | .id'; }
open_foot() { niri msg action spawn -- foot -c /dev/null -a "$1"; until_ok 5000 window_of "$1" >/dev/null; }

until_ok 2000 mode_is rest
open_foot foot
foot=$(window_of foot)

cast 1001 1001 "{\"Window\":{\"id\":$foot}}"
until_ok 2000 reads "LIVE FOOT"
check "a portal share of a foot window reads LIVE FOOT ($(island_text))" reads "LIVE FOOT"

cast 1002 1002 '{"Output":{"name":"winit"}}'
until_ok 2000 reads "LIVE ×2"
check "two shares at once read LIVE ×2" reads "LIVE ×2"
uncast 1002

cast 1001 1001 '"Nothing"'
until_ok 2000 reads "LIVE NOTHING"
check "a share whose target was cleared reads LIVE NOTHING" reads "LIVE NOTHING"

cast 1001 1001 '{"Output":{"name":"winit"}}' false
until_ok 2000 reads "LIVE PAUSED"
check "a share niri reports inactive reads LIVE PAUSED" reads "LIVE PAUSED"

# The relay adds its casts to niri's CastsChanged, so a shell started during a share hears of it in the first burst.
systemctl --user restart "$DOTS_DEV_UNIT"
until_ok 10000 shell_status >/dev/null
until_ok 3000 reads "LIVE PAUSED"
check "a shell started during a share reads it from the first burst" reads "LIVE PAUSED"
uncast 1001
until_ok 2000 mode_is rest

# An app id is the app's to choose: a forged one draws on one line, inside the 560 px box.
open_foot $'a\nb‮evil\e[31m'
cast 1003 1003 "{\"Window\":{\"id\":$(window_of $'a\nb‮evil\e[31m')}}"
until_ok 2000 mode_is sharing
check "an app id of a newline, U+202E and ESC reads on one line ($(island_text))" reads "LIVE A BEVIL [31M"
uncast 1003
long=$(printf 'x%.0s' $(seq 200))
open_foot "$long"
cast 1004 1004 "{\"Window\":{\"id\":$(window_of "$long")}}"
until_ok 2000 mode_is sharing
settled() { island | jq -e '.animating == false' >/dev/null; }
until_ok 3000 settled
check "a 200-character app id stays inside the 560 px box ($(island | jq -c '{width, drawn}'))" bash -c '[ "$(timeout 0.5 qs ipc call island state | jq ".drawn <= 560 and .width == 560")" = true ]'
uncast 1004

exit $((fails > 0))
}
