#!/usr/bin/env bash
# Mod+I on LIVE opens a card of the shares and who watches each; Enter stops every PipeWire session once, Esc stops nothing.
{
export DOTS_DEV_FAKE_CASTS=1
source "$(dirname "$0")/lib.sh"

island() { timeout 0.5 qs ipc call island state 2>/dev/null; }
island_text() { island | jq -r .text; }
reads() { [ "$(island_text)" = "$1" ]; }
mode_is() { island | jq -e --arg m "$1" '.mode == $m' >/dev/null; }
rows() { island | jq -c '[.sharing.rows[] | [.text, .stop]]'; }
rows_are() { [ "$(rows)" = "$1" ]; }
island_focus() { niri msg -j layers | jq -e --arg k "$1" 'any(.[]; .namespace == "dots-island" and .keyboard_interactivity == $k)' >/dev/null; }
# niri runs no binds for wtype's virtual keyboard, so the check spawns Mod+I's command.
mod_i() { niri msg action spawn -- dots-call island focus; until_ok 2000 mode_is sharingCard; until_ok 2000 island_focus Exclusive; }
# cast <stream> <session> <target json> [kind] [pid]: a cast as niri reports it, PipeWire unless said.
cast() { fake_event "{\"CastStartedOrChanged\":{\"cast\":{\"stream_id\":$1,\"session_id\":$2,\"kind\":\"${4:-PipeWire}\",\"target\":$3,\"is_dynamic_target\":false,\"is_active\":true,\"pid\":${5:-null},\"pw_node_id\":null}}}" >/dev/null; }
uncast() { fake_event "{\"CastStopped\":{\"stream_id\":$1}}" >/dev/null; }
SCREEN='{"Output":{"name":"winit"}}'
# The stops run at once, so they land in any order.
stops() { relay_stops | sort -n | paste -sd' '; }
wf=
named=
cleanup() {
  [ -z "$wf" ] || { kill -INT "$wf"; wait "$wf" 2>/dev/null || true; }
  [ -z "$named" ] || kill "$named" 2>/dev/null
}

wf-recorder -y -f "$DOTS_DEV_DIR/share.mp4" >/dev/null 2>&1 &
wf=$!
until_ok 3000 reads "LIVE SCREEN"
mod_i
until_ok 2000 rows_are '[["SCREEN  wf-recorder",false]]'
check "Mod+I on a wf-recorder share: one row, SCREEN  wf-recorder, with no ↵ stop ($(rows))" rows_are '[["SCREEN  wf-recorder",false]]'
check "the card has the keyboard" island_focus Exclusive
wtype -k Return
until_ok 2000 mode_is sharing
check "Enter on a card of screencopy rows stops nothing and closes it" mode_is sharing
check "wf-recorder still runs" kill -0 "$wf"
check "and nothing was asked to stop ($(stops))" test -z "$(stops)"
check "the island gives the keyboard back" island_focus None

cast 2001 2001 "$SCREEN"
until_ok 2000 reads "LIVE ×2"
mod_i
until_ok 2000 rows_are '[["SCREEN  wf-recorder",false],["SCREEN  portal share",true]]'
check "a portal share's row reads SCREEN  portal share with ↵ stop ($(rows))" rows_are '[["SCREEN  wf-recorder",false],["SCREEN  portal share",true]]'
check "island state reads the card's rows ($(island_text))" reads "SCREEN  wf-recorder · SCREEN  portal share  ↵ stop"
wtype -k Return
until_ok 2000 reads "LIVE SCREEN"
check "Enter stops the portal share and leaves wf-recorder's ($(island_text))" reads "LIVE SCREEN"
check "with one stop-cast, for its session ($(stops))" test "$(stops)" = 2001
check "wf-recorder still runs" kill -0 "$wf"
check "niri still lists only the WlrScreencopy cast" bash -c '[ "$(niri msg -j casts | jq -c "map(.kind)")" = "[\"WlrScreencopy\"]" ]'
kill -INT "$wf"
wait "$wf" 2>/dev/null
wf=
until_ok 2000 mode_is rest

# A portal session can hold two streams; it is stopped once.
: >"$DOTS_DEV_DIR/niri-relay-stops"
cast 2002 2002 "$SCREEN"
cast 2003 2003 '"Nothing"'
cast 2004 2004 "$SCREEN"
cast 2005 2004 "$SCREEN"
until_ok 2000 reads "LIVE ×4"
mod_i
wtype -k Return
until_ok 2000 mode_is rest
check "Enter stops two sessions' shares and a two-stream session's, back to the clock" mode_is rest
check "one stop-cast per session ($(stops))" test "$(stops)" = "2002 2003 2004"

: >"$DOTS_DEV_DIR/niri-relay-stops"
cast 2006 2006 "$SCREEN"
until_ok 2000 reads "LIVE SCREEN"
mod_i
wtype -k Escape
until_ok 2000 mode_is sharing
check "Esc closes the card with the share still LIVE" reads "LIVE SCREEN"
check "and nothing asked to stop ($(stops))" test -z "$(stops)"
check "and gives the keyboard back" island_focus None

# A share that ends on its own while the card is open takes the card with it.
mod_i
uncast 2006
until_ok 2000 mode_is rest
check "the card closes when its last share ends on its own" mode_is rest
check "and gives the keyboard back" island_focus None

# An app id and a process name are their owners' to choose: each row stays one line, elided inside the card.
long=$(printf 'x%.0s' $(seq 200))
niri msg action spawn -- foot -c /dev/null -a "$long"
window_of() { niri msg -j windows | jq -e --arg a "$1" 'first(.[] | select(.app_id == $a)) | .id'; }
until_ok 5000 window_of "$long" >/dev/null
cast 2007 2007 "{\"Window\":{\"id\":$(window_of "$long")}}"
# comm holds 15 bytes, room for a newline, U+202E and an ESC sequence, written at once: bash's printf would end the name at its newline.
python3 -c 'import os, time; fd = os.open("/proc/self/comm", os.O_WRONLY); os.write(fd, "a\nb\u202e\x1b[31m".encode()); time.sleep(600)' &
named=$!
cast 2008 2008 "$SCREEN" WlrScreencopy "$named"
until_ok 2000 reads "LIVE ×2"
mod_i
until_ok 2000 eval '[ "$(island | jq ".sharing.rows | length")" = 2 ] && [ "$(rows | jq -r ".[1][0]")" = "SCREEN  a b [31m" ]'
check "a process named with a newline, U+202E and ESC reads on one line ($(rows | jq -c '.[1]'))" bash -c '[ "$(timeout 0.5 qs ipc call island state | jq -r ".sharing.rows[1].text")" = "SCREEN  a b [31m" ]'
check "a 200-character app id's row is one line, elided inside the card ($(island | jq -c '.sharing | {inner, row: (.rows[0] | {lines, elided, width})}'))" bash -c 'timeout 0.5 qs ipc call island state | jq -e ".sharing as \$s | \$s.rows[0].lines == 1 and \$s.rows[0].elided and \$s.rows[0].width <= \$s.inner and \$s.rows[1].lines == 1" >/dev/null'
wtype -k Escape

exit $((fails > 0))
}
