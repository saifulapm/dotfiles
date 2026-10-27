#!/usr/bin/env bash
# With DOTS_DEV_FAKE_CASTS=1 the shell reads niri through a relay that can show casts niri cannot make here; without it the shell reads niri itself.
{
if [ "${1:-}" != plain ]; then
  # The plain session runs first and alone: lib.sh's lock is not taken until it is sourced.
  bash "$0" plain || plain_rc=1
  export DOTS_DEV_FAKE_CASTS=1
fi
source "$(dirname "$0")/lib.sh"

unit_socket() { systemctl --user show "$DOTS_DEV_UNIT" -p Environment --value | tr ' ' '\n' | sed -n 's/^NIRI_SOCKET=//p'; }
surfaces_focus() { niri msg -j layers | jq -e --arg k "$1" 'any(.[]; .namespace == "dots-surfaces" and .keyboard_interactivity == $k)' >/dev/null; }

if [ "${1:-}" = plain ]; then
  unit_is_niri() { [ "$(unit_socket)" = "$NIRI_SOCKET" ]; }
  check "without the variable the shell unit's NIRI_SOCKET is niri's own" unit_is_niri
else
  relay=$DOTS_DEV_DIR/niri-relay.sock
  unit_is_relay() { [ "$(unit_socket)" = "$relay" ]; }
  check_is_niri() { [ "$NIRI_SOCKET" != "$relay" ]; }
  check "the shell unit's NIRI_SOCKET is the relay" unit_is_relay
  check "the check's own NIRI_SOCKET is still niri's" check_is_niri

  niri msg action open-overview
  until_ok 2000 surfaces_focus Exclusive
  check "the shell follows niri through the relay: it takes the keys in the overview" surfaces_focus Exclusive
  niri msg action close-overview
  until_ok 2000 surfaces_focus None

  fake_event '{"CastStartedOrChanged":{"cast":{"stream_id":901,"session_id":77,"kind":"PipeWire","target":"Nothing","is_dynamic_target":false,"is_active":true,"pid":null,"pw_node_id":5}}}' >/dev/null
  stop_fake() { NIRI_SOCKET=$relay niri msg action stop-cast --session-id 77; }
  logged_77() { [ "$(relay_stops)" = 77 ]; }
  check "stop-cast for a fake session through the relay exits 0" stop_fake
  check "and the relay logged session 77" logged_77
fi

exit $((fails > 0 || ${plain_rc:-0} > 0))
}
