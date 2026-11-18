#!/usr/bin/env bash
# gpg's passphrase prompt takes the island over as board 7's 520 px prompt, with Cancel and an inverted Unlock; a wrong passphrase clears its field and draws one danger line; over Pass it leaves Pass open with its query and selection and the copy done, with Copied at its foot; a polkit prompt over it names GPG and gives it back; what is typed reaches no state; a second request waits; over a fullscreen window it still shows.
{
source "$(dirname "$0")/lib.sh"

island() { timeout 0.5 qs ipc call island state 2>/dev/null; }
island_is() { island | jq -e "$@" >/dev/null 2>&1; }
pin() { timeout 0.5 qs ipc call pinentry state 2>/dev/null; }
pin_is() { pin | jq -e "$@" >/dev/null 2>&1; }
pass_state() { timeout 0.5 qs ipc call pass state 2>/dev/null; }
pass_is() { pass_state | jq -e "$@" >/dev/null 2>&1; }
pk() { timeout 0.5 qs ipc call polkit state 2>/dev/null; }
pk_is() { pk | jq -e "$@" >/dev/null 2>&1; }
# pkexec is setuid and always reaches the live polkitd, so a fake authority on the nested bus asks the nested shell's agent instead (2N8SVRBX).
fake() { busctl --address="$DBUS_SESSION_BUS_ADDRESS" call org.freedesktop.PolicyKit1 /org/freedesktop/PolicyKit1/Authority org.dots.FakePolkit "$@"; }
result_is() { [ "$(fake Result s "$1" 2>/dev/null)" = "s \"$2\"" ]; }
prompt_up() { island_is '.takeover == "pinentry" and .animating == false' && pin_is '.open and .settled and .keyboard'; }
open_pass() {
  niri msg action spawn -- dots-call pass toggle
  until_ok 3000 pass_is '.open and .listed and .settled and .keyboard'
}
clip() { timeout 1 wl-paste -n 2>/dev/null; }
exited() { ! kill -0 "$1" 2>/dev/null; }
rc_of() {
  wait "$1"
  echo $?
}
# Not in a subshell, so its pid stays this shell's child for wait.
show_bg() {
  pass show web/github.com >"$out/$1.out" 2>"$out/$1.err" 9>&- &
  pid=$!
}
ask() { printf 'SETDESC %s\nSETPROMPT Secret:\nGETPIN\nBYE\n' "$1" | "$repo/bin/dots-pinentry" >"$out/$1.assuan" 9>&- & echo $!; }

# bin/dots-dev points the store and the keyring into its temp dir, so nothing here reaches ~/.password-store or ~/.gnupg (2N8SVRBX).
: "${PASSWORD_STORE_DIR:?}" "${GNUPGHOME:?}"
out=$(mktemp -d)
DBUS_SYSTEM_BUS_ADDRESS=$DBUS_SESSION_BUS_ADDRESS "$repo/bin/dev-fake-polkit" 9>&- &
fake_pid=$!
cleanup() {
  kill "$fake_pid" 2>/dev/null
  gpgconf --kill gpg-agent 2>/dev/null
  rm -rf "$out"
}
mkdir -p -m 700 "$GNUPGHOME"
passphrase=zq9xkvwj-phrase wrong=wrongkvz-try password=hunter2-correct-horse
unset PINENTRY_USER_DATA GPG_TTY
echo "pinentry-program $repo/bin/dots-pinentry" >"$GNUPGHOME/gpg-agent.conf"
gpg --batch --pinentry-mode loopback --passphrase "$passphrase" --quick-gen-key 'Dots Test <dots@test>' default default never 2>/dev/null
pass init dots@test >/dev/null
for e in web/github.com web/gitlab.com mail/icloud; do printf '%s\n' "$password-$e" | pass insert -e "$e" >/dev/null; done
printf '%s\n' "$password" | pass insert -f -e web/github.com >/dev/null
gpgconf --kill gpg-agent
until_ok 3000 fake Registered >/dev/null 2>&1
# The agent registers as the shell starts, so the shell restarts once the authority is up.
systemctl --user restart "$DOTS_DEV_UNIT"
until_ok 5000 pk_is .registered
until_ok 3000 island_is '.surface == null and .takeover == null and .animating == false'

# A cold agent asks for the passphrase over the resting island.
show_bg first
until_ok 8000 prompt_up
check "a getpin request sets takeover to pinentry ($(island | jq -c '{surface, takeover}'))" island_is '.takeover == "pinentry"'
check "the prompt is 520 px wide ($(pin | jq .width))" pin_is '.width == 520 and (.description | startswith("Please enter the pas"))'
check "it has Cancel and an inverted Unlock, and a masked 44 px field ($(pin | jq -c '{buttons: [.buttons[] | {text, inverted}], drawnField}'))" \
  pin_is '([.buttons[] | [.text, .inverted]] == [["Cancel", false], ["Unlock", true]]) and .drawnField.h == 44 and .drawnField.secret'

# A wrong passphrase: gpg asks again with its error, the field empty and one line in the danger tone.
wtype "$wrong"
until_ok 2000 pin_is ".field == ${#wrong}"
check "what is typed is in no state: island, pinentry, pass" bash -c "! { timeout 0.5 qs ipc call island state; timeout 0.5 qs ipc call pinentry state; timeout 0.5 qs ipc call pass state; } | grep -qF '$wrong'"
wtype -k Return
until_ok 9000 pin_is '.open and .wrong != null and .field == 0'
check "a wrong passphrase gives the prompt again with an empty field and one danger line ($(pin | jq -c '{field, wrong, danger}'))" \
  pin_is '.open and .field == 0 and .wrong.text == "Bad passphrase · try 2 of 3" and (.wrong.color | ascii_downcase) == (.danger | ascii_downcase)'

# The right one answers gpg, and pass show prints the password.
until_ok 3000 prompt_up
wtype "$passphrase"
until_ok 2000 pin_is ".field == ${#passphrase}"
wtype -k Return
until_ok 8000 exited "$pid"
rc=$(rc_of "$pid")
check "the passphrase and Enter answer gpg: pass show exits 0 (rc $rc)" test "$rc" = 0
check "and prints the password" grep -qxF "$password" "$out/first.out"
until_ok 3000 island_is '.takeover == null'
check "the island is handed back ($(island | jq -c '{surface, takeover}'))" island_is '.takeover == null'

# Over Pass: the copy that needs gpg leaves Pass open with its query and selection.
gpgconf --kill gpg-agent
open_pass
wtype web
until_ok 2000 pass_is '.query == "web" and .count == 2'
wtype -k Down
until_ok 2000 pass_is '.selected == 1'
want=$(pass_state | jq -r '.rows[.selected].name')
wtype -k Return
until_ok 8000 prompt_up
check "Enter on an entry with a cold agent draws the gpg prompt over Pass: takeover pinentry, surface pass, chip Pass ($(island | jq -c '{surface, takeover}'), $(pin | jq -c .chip))" \
  eval 'island_is ".surface == \"pass\" and .takeover == \"pinentry\"" && pin_is ".chip == \"Pass\""'
check "Pass is still open under it with its query ($(pass_state | jq -c '{open, query, selected}'))" pass_is '.open and .query == "web" and .selected == 1'

# A polkit request over the gpg prompt names GPG, and Esc gives the gpg prompt back.
fake Begin s t1 >/dev/null
until_ok 3000 island_is '.takeover == "polkit" and .animating == false'
until_ok 2000 pk_is '.open and .settled and .keyboard'
check "polkit over gpg: its chip reads GPG ($(pk | jq -c .chip))" pk_is '.chip == "GPG"'
wtype -k Escape
until_ok 3000 result_is t1 org.freedesktop.PolicyKit1.Error.Cancelled
until_ok 3000 prompt_up
check "Esc on polkit returns to the gpg prompt, still over Pass ($(island | jq -c '{surface, takeover}'))" island_is '.takeover == "pinentry" and .surface == "pass"'
wtype "$passphrase"
until_ok 2000 pin_is ".field == ${#passphrase}"
check "what is typed here is in no state either" bash -c "! { timeout 0.5 qs ipc call island state; timeout 0.5 qs ipc call pinentry state; timeout 0.5 qs ipc call pass state; } | grep -qF '$passphrase'"
wtype -k Return

# Answered, it returns to Pass: same query and selection, the password copied, Copied at the foot.
until_ok 8000 island_is '.takeover == null and .animating == false'
until_ok 5000 bash -c "[ \"\$(timeout 1 wl-paste -n 2>/dev/null)\" = '$password-$want' ]"
check "after the passphrase the island is handed back to Pass ($(island | jq -c '{surface, takeover}'))" island_is '.takeover == null and .surface == "pass"'
check "Pass is open with the same query and selection ($(pass_state | jq -c '{open, query, selected}'))" pass_is '.open and .query == "web" and .selected == 1'
check "wl-paste gives the password of $want" test "$(clip)" = "$password-$want"
until_ok 3000 pass_is '.note | test("^Copied")'
check "Pass's foot reads Copied ($(pass_state | jq -c .note))" pass_is '.note | test("^Copied")'
wtype -k Escape
until_ok 3000 island_is '.surface == null'

# A second request waits behind the first and shows after it.
a=$(ask first-request)
until_ok 3000 pin_is '.open and .description == "first-request"'
b=$(ask second-request)
until_ok 3000 pin_is '.waiting == 1'
check "a second request while one shows waits ($(pin | jq -c '{description, waiting}'))" pin_is '.open and .description == "first-request" and .waiting == 1'
until_ok 3000 prompt_up
wtype one
until_ok 2000 pin_is '.field == 3'
wtype -k Return
until_ok 3000 pin_is '.open and .description == "second-request" and .waiting == 0'
check "and shows after the first is answered ($(pin | jq -c '{description, waiting}'))" pin_is '.open and .description == "second-request" and .waiting == 0'
until_ok 3000 prompt_up
wtype -k Escape
until_ok 3000 exited "$b"
until_ok 3000 island_is '.takeover == null'

# Over a fullscreen window the prompt still shows.
niri msg action spawn -- foot -c /dev/null sh -c 'sleep 600'
until_ok 5000 bash -c '[ "$(niri msg -j focused-window | jq -r .app_id)" = foot ]'
niri msg action fullscreen-window
until_ok 3000 island_is '.shown == false'
c=$(ask fullscreen-request)
until_ok 3000 prompt_up
check "over a fullscreen window the gpg prompt shows ($(island | jq -c '{shown, takeover}'))" island_is '.shown and .takeover == "pinentry"'
wtype -k Escape
until_ok 3000 exited "$c"
until_ok 3000 island_is '.takeover == null and .shown == false'
niri msg action close-window

exit $((fails > 0))
}
