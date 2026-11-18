#!/usr/bin/env bash
# A polkit request takes the island over: over the launcher with fo typed it draws board 7's 520 px prompt with a Launcher chip, and Esc, a hang-up or an answer hands the launcher back with fo; at rest it has no chip and leaves the clock; mid-morph it still lands over the launcher; a notification waits under it; nothing typed into it reaches any state; a surface's key does nothing while it shows.
{
source "$(dirname "$0")/lib.sh"

island() { timeout 0.5 qs ipc call island state 2>/dev/null; }
island_is() { island | jq -e "$@" >/dev/null 2>&1; }
launcher() { timeout 0.5 qs ipc call launcher state 2>/dev/null; }
launcher_is() { launcher | jq -e "$@" >/dev/null 2>&1; }
pk() { timeout 0.5 qs ipc call polkit state 2>/dev/null; }
pk_is() { pk | jq -e "$@" >/dev/null 2>&1; }
surfaces_focus() { niri msg -j layers | jq -e --arg k "$1" 'any(.[]; .namespace == "dots-surfaces" and .keyboard_interactivity == $k)' >/dev/null; }
# pkexec is setuid and always reaches the live polkitd, so a fake authority on the nested bus asks the nested shell's agent instead (2N8SVRBX).
fake() { busctl --address="$DBUS_SESSION_BUS_ADDRESS" call org.freedesktop.PolicyKit1 /org/freedesktop/PolicyKit1/Authority org.dots.FakePolkit "$@"; }
result_is() { [ "$(fake Result s "$1" 2>/dev/null)" = "s \"$2\"" ]; }
open_launcher() {
  niri msg action spawn -- dots-call launcher toggle
  until_ok 3000 island_is '.surface == "launcher" and .animating == false'
  until_ok 2000 launcher_is '.keyboard and .settled'
}
prompt_up() { island_is '.takeover == "polkit" and .animating == false' && pk_is '.open and .settled and .keyboard'; }
rest() { island_is '.surface == null and .takeover == null and .mode == "rest" and .animating == false'; }

DBUS_SYSTEM_BUS_ADDRESS=$DBUS_SESSION_BUS_ADDRESS "$repo/bin/dev-fake-polkit" 9>&- &
fake_pid=$!
cleanup() { kill "$fake_pid" 2>/dev/null; }
until_ok 3000 fake Registered >/dev/null 2>&1
# The agent registers as the shell starts, so the shell restarts once the authority is up.
systemctl --user restart "$DOTS_DEV_UNIT"
until_ok 5000 pk_is .registered
until_ok 3000 rest

# Over the launcher with fo typed.
open_launcher
wtype fo
until_ok 2000 launcher_is '.query == "fo"'
fake Begin s t1 >/dev/null
until_ok 3000 prompt_up
check "a request sets takeover to polkit and surface stays launcher ($(island | jq -c '{surface, takeover}'))" island_is '.surface == "launcher" and .takeover == "polkit"'
check "the island is 520 px wide for it ($(island | jq .width))" island_is '.width == 520'
check "the prompt's chip reads Launcher ($(pk | jq -c .chip))" pk_is '.chip == "Launcher"'
check "it is board 7's prompt: a title, the request, a field, then Cancel and an inverted Allow ($(pk | jq -c '{title, drawnMessage, drawnField, buttons: [.buttons[] | {text, inverted}]}'))" \
  pk_is '.title != "" and (.drawnMessage | test("run true as root")) and .drawnField.h == 44 and .drawnField.secret and ([.buttons[] | [.text, .inverted]] == [["Cancel", false], ["Allow", true]])'
check "the launcher is still open under it, with fo ($(launcher | jq -c '{open, query}'))" launcher_is '.open and .query == "fo"'

# A secret typed into the prompt reaches no state, and not the launcher's query.
wtype hunter2
until_ok 2000 pk_is '.field == 7'
check "the typed password is in no state: island, polkit, launcher" bash -c '! { timeout 0.5 qs ipc call island state; timeout 0.5 qs ipc call polkit state; timeout 0.5 qs ipc call launcher state; } | grep -q hunter2'
check "the launcher's query is still fo ($(launcher | jq -c .query))" launcher_is '.query == "fo"'

# A wrong password clears the field and draws one danger line; the prompt stays.
wtype -k Return
until_ok 9000 pk_is '.wrong != null and .field == 0'
check "a wrong password clears the field and draws one line in the danger tone; the prompt stays ($(pk | jq -c '{open, field, wrong, danger}'))" pk_is '.open and .field == 0 and .wrong.text != "" and (.wrong.color | ascii_downcase) == (.danger | ascii_downcase)'

# Esc hands the launcher back, with its query and the keyboard.
check "the prompt still holds the keyboard after the wrong password ($(pk | jq -c "{keyboard, field}"))" pk_is ".keyboard"
wtype -k Escape
until_ok 3000 result_is t1 org.freedesktop.PolicyKit1.Error.Cancelled
until_ok 3000 island_is '.takeover == null and .surface == "launcher" and .animating == false'
check "Esc cancels the request and sets takeover to null ($(island | jq -c '{surface, takeover}'))" island_is '.takeover == null and .surface == "launcher"'
check "the launcher is back open with fo ($(launcher | jq -c '{open, query}'))" launcher_is '.open and .query == "fo"'
check "the island is the launcher's width again ($(island | jq .width))" island_is '.width != 520'
until_ok 2000 launcher_is '.keyboard'
wtype o
until_ok 2000 launcher_is '.query == "foo"'
check "the launcher has the keyboard again: o makes foo ($(launcher | jq -c .query))" launcher_is '.query == "foo"'

# The caller going away hands the launcher back the same way.
fake Begin s t2 >/dev/null
until_ok 3000 prompt_up
fake Cancel s t2 >/dev/null
until_ok 3000 island_is '.takeover == null and .surface == "launcher"'
check "a hang-up sets takeover to null and the launcher is back with foo ($(island | jq -c '{surface, takeover}'), $(launcher | jq -c .query))" eval 'island_is ".takeover == null and .surface == \"launcher\"" && launcher_is ".open and .query == \"foo\""'

# A surface's key while the prompt shows does nothing: the launcher stays under it and the request stays.
fake Begin s t3 >/dev/null
until_ok 3000 prompt_up
niri msg action spawn -- dots-call launcher toggle
niri msg action spawn -- dots-call control toggle
sleep 0.5
check "Mod+Space and Mod+C while the prompt shows change nothing ($(island | jq -c '{surface, takeover}'))" eval 'island_is ".takeover == \"polkit\" and .surface == \"launcher\"" && result_is t3 pending'

# A notification arriving under the prompt waits, and shows once nothing holds the island.
notify-send under-prompt
until_ok 2000 island_is '.waiting == 1'
check "a notification under the prompt waits ($(island | jq -c '{mode, waiting, takeover}'))" island_is '.waiting == 1 and .takeover == "polkit"'
# The prompt holds the keys, and the toggles above opened nothing.
wtype -k Escape # early on purpose
until_ok 3000 island_is '.takeover == null'
niri msg action spawn -- dots-call launcher toggle
until_ok 3000 island_is '.mode == "notification"'
check "once the launcher closes the notification shows ($(island | jq -c '{mode, text}'))" island_is '.mode == "notification"'
until_ok 8000 rest

# At rest: no chip, and the island goes back to the clock.
fake Begin s t4 >/dev/null
until_ok 3000 prompt_up
check "a prompt over the resting island has no chip and no surface under it ($(pk | jq -c .chip), $(island | jq -c '{surface}'))" eval 'pk_is ".chip == null" && island_is ".surface == null"'
wtype -k Escape
until_ok 3000 rest
check "after it the island is the clock again ($(island | jq -c '{mode, width}'))" rest

# Mid-morph: a request 100 ms after Mod+Space still lands over the launcher.
niri msg action spawn -- dots-call launcher toggle
sleep 0.1
fake Begin s t5 >/dev/null
until_ok 3000 prompt_up
check "a request 100 ms after Mod+Space ends with takeover polkit over surface launcher ($(island | jq -c '{surface, takeover}'))" island_is '.surface == "launcher" and .takeover == "polkit"'
check "and its chip reads Launcher" pk_is '.chip == "Launcher"'
wtype -k Escape
until_ok 3000 island_is '.takeover == null and .surface == "launcher" and .animating == false'
check "Esc then leaves the launcher open ($(island | jq -c '{surface, takeover}'))" island_is '.surface == "launcher"'
wtype -k Escape
until_ok 3000 rest

# Over a fullscreen window the prompt still shows (BRQAT409).
niri msg action spawn -- foot -c /dev/null sh -c 'sleep 600'
until_ok 5000 bash -c '[ "$(niri msg -j focused-window | jq -r .app_id)" = foot ]'
niri msg action fullscreen-window
until_ok 3000 island_is '.shown == false'
fake Begin s t6 >/dev/null
until_ok 3000 prompt_up
check "over a fullscreen window the prompt shows ($(island | jq -c '{shown, takeover}'))" island_is '.shown and .takeover == "polkit"'
wtype -k Escape
until_ok 3000 island_is '.takeover == null and .shown == false'
check "and after it the island hides again" island_is '.takeover == null and .shown == false'
niri msg action close-window

exit $((fails > 0))
}
