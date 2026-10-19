#!/usr/bin/env bash
# A polkit request shows the shell's one prompt with exclusive keyboard, and Esc cancels the request.
{
source "$(dirname "$0")/lib.sh"

# pkexec is setuid and always reaches the live polkitd, so a fake authority on the nested bus asks the nested shell's agent instead.
fake() { busctl --address="$DBUS_SESSION_BUS_ADDRESS" call org.freedesktop.PolicyKit1 /org/freedesktop/PolicyKit1/Authority org.dots.FakePolkit "$@"; }
pk_state() { timeout 0.5 qs ipc call polkit state 2>/dev/null; }
state_is() { pk_state | jq -e "$1" >/dev/null; }
focus_is() { niri msg -j layers | jq -e --arg k "$1" 'any(.[]; .namespace == "dots-surfaces" and .keyboard_interactivity == $k)' >/dev/null; }
# busctl prints a string reply as s "<value>".
result_is() { [ "$(fake Result s "$1" 2>/dev/null)" = "s \"$2\"" ]; }

DBUS_SYSTEM_BUS_ADDRESS=$DBUS_SESSION_BUS_ADDRESS "$repo/bin/dev-fake-polkit" &
fake_pid=$!
cleanup() { kill "$fake_pid" 2>/dev/null; }
until_ok 3000 fake Registered >/dev/null 2>&1
# The agent registers as the shell starts, so the shell restarts once the authority is up.
systemctl --user restart "$DOTS_DEV_UNIT"
until_ok 5000 state_is .registered
check "the shell's agent registers with the authority" state_is .registered

fake Begin s c1 >/dev/null
until_ok 3000 state_is '.open'
check "a request shows the prompt with its message" state_is '.open and (.message | test("run true as root"))'
check "the prompt holds the keyboard" focus_is Exclusive
wtype abc
until_ok 2000 state_is '.field == 3'
wtype -k Escape
until_ok 3000 result_is c1 org.freedesktop.PolicyKit1.Error.Cancelled
check "Esc cancels the request (BeginAuthentication returns Cancelled)" result_is c1 org.freedesktop.PolicyKit1.Error.Cancelled
until_ok 2000 state_is '(.open | not) and (.active | not)'
check "the prompt closes and the agent goes idle" state_is '(.open | not) and (.active | not)'
check "the keyboard goes back" focus_is None

# A request that arrives while the prompt is up is refused at once, so its caller gets an answer, and the shown one carries on.
fake Begin s c2 >/dev/null
until_ok 3000 state_is '.open'
fake Begin s c3 >/dev/null
until_ok 3000 result_is c3 org.freedesktop.PolicyKit1.Error.Cancelled
check "a second request while the prompt is up is cancelled" result_is c3 org.freedesktop.PolicyKit1.Error.Cancelled
check "and the first still shows, waiting" bash -c "[ \"\$(busctl --address=\"$DBUS_SESSION_BUS_ADDRESS\" call org.freedesktop.PolicyKit1 /org/freedesktop/PolicyKit1/Authority org.dots.FakePolkit Result s c2)\" = 's \"pending\"' ] && timeout 0.5 qs ipc call polkit state | jq -e '.open and (.message | test(\"run true\"))' >/dev/null"
wtype -k Escape
until_ok 3000 result_is c2 org.freedesktop.PolicyKit1.Error.Cancelled
check "Esc then cancels the first" result_is c2 org.freedesktop.PolicyKit1.Error.Cancelled
until_ok 2000 state_is '.open | not'
check "and the prompt closes" state_is '.open | not'

# The key hint reads in each theme's voice: Artboard plain, Blueprint bracketed, Paper caps.
status_theme() { shell_status | jq -e --arg t "$1" '.theme == $t' >/dev/null; }
in_theme() { "$repo/bin/dots" theme "$1" >/dev/null; until_ok 2000 status_theme "$1"; }
n=0
for t in "artboard|↵ authenticate  esc cancel" "blueprint|[↵] AUTHENTICATE  [ESC] CANCEL" "paper|↵ AUTHENTICATE  ESC CANCEL"; do
  n=$((n + 1))
  in_theme "${t%%|*}"
  fake Begin s "h$n" >/dev/null
  until_ok 3000 state_is '.open'
  check "${t%%|*}: the hint reads ${t#*|} ($(pk_state | jq -c .hint))" state_is ".hint == \"${t#*|}\""
  wtype -k Escape
  until_ok 3000 result_is "h$n" org.freedesktop.PolicyKit1.Error.Cancelled
  until_ok 2000 state_is '.open | not'
done

exit $((fails > 0))
}
