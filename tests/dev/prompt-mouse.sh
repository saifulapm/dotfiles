#!/usr/bin/env bash
# The polkit and pinentry cards by mouse: a click on the ↵ chip answers as Enter does, and a click on the esc chip cancels as Esc does.
{
source "$(dirname "$0")/lib.sh"
source "$(dirname "$0")/pointer.bash"

# pkexec reaches the live polkitd, so a fake authority on the nested bus asks the nested shell's agent instead (as tests/dev/polkit.sh does).
fake() { busctl --address="$DBUS_SESSION_BUS_ADDRESS" call org.freedesktop.PolicyKit1 /org/freedesktop/PolicyKit1/Authority org.dots.FakePolkit "$@"; }
pk_state() { timeout 0.5 qs ipc call polkit state 2>/dev/null; }
pk_is() { pk_state | jq -e "$1" >/dev/null 2>&1; }
result_is() { [ "$(fake Result s "$1" 2>/dev/null)" = "s \"$2\"" ]; }
pin_state() { timeout 0.5 dots-call pinentry state 2>/dev/null; }
pin_is() { pin_state | jq -e "$1" >/dev/null 2>&1; }
out=$(mktemp -d)
DBUS_SYSTEM_BUS_ADDRESS=$DBUS_SESSION_BUS_ADDRESS "$repo/bin/dev-fake-polkit" &
fake_pid=$!
cleanup() {
  pointer_stop
  kill "$fake_pid" 2>/dev/null
  rm -rf "$out"
}
until_ok 3000 fake Registered >/dev/null 2>&1
systemctl --user restart "$DOTS_DEV_UNIT"
until_ok 5000 pk_is .registered

fake Begin s m1 >/dev/null
until_ok 3000 pk_is '.open and .settled'
wtype abc
until_ok 2000 pk_is '.field == 3'
click_box polkit-key:0
until_ok 2000 pk_is '.submits == 1'
check "a click on polkit's ↵ chip hands the typed password to the request, as Enter does ($(pk_state | jq -c '{submits, field}'))" pk_is '.submits == 1 and .field == 0'
until_ok 5000 pk_is '.open and .settled'
click_box polkit-key:1
until_ok 3000 result_is m1 org.freedesktop.PolicyKit1.Error.Cancelled
check "a click on its esc chip cancels the request" result_is m1 org.freedesktop.PolicyKit1.Error.Cancelled
until_ok 2000 pk_is '.open | not'
check "and the prompt closes" pk_is '.open | not'

printf 'SETDESC typed-request\nSETPROMPT Secret:\nGETPIN\nBYE\n' | "$repo/bin/dots-pinentry" >"$out/typed.assuan" &
until_ok 3000 pin_is '.open and .description == "typed-request"'
wtype one
click_box pinentry-key:0
until_ok 3000 grep -qx 'D one' "$out/typed.assuan"
check "a click on pinentry's ↵ chip answers with what was typed" grep -qx 'D one' "$out/typed.assuan"

printf 'SETDESC confirm-request\nCONFIRM\nBYE\n' | "$repo/bin/dots-pinentry" >"$out/confirm.assuan" &
until_ok 3000 pin_is '.open and .description == "confirm-request"'
click_box pinentry-key:0
# Allowed, CONFIRM answers OK; denied, it answers ERR, and gpg reads OK closing connection only once the card has answered.
allowed=$'OK Pleased to meet you\nOK\nOK\nOK closing connection'
until_ok 3000 grep -q '^OK closing connection' "$out/confirm.assuan"
check "a click on a confirm card's ↵ allow chip allows it ($(tr '\n' ' ' <"$out/confirm.assuan"))" test "$(cat "$out/confirm.assuan")" = "$allowed"

printf 'SETDESC cancel-request\nSETPROMPT Secret:\nGETPIN\nBYE\n' | "$repo/bin/dots-pinentry" >"$out/cancel.assuan" &
until_ok 3000 pin_is '.open and .description == "cancel-request"'
click_box pinentry-key:1
until_ok 3000 grep -q '^ERR 83886179' "$out/cancel.assuan"
check "a click on its esc chip cancels" grep -q '^ERR 83886179' "$out/cancel.assuan"

exit "$fails"
}
