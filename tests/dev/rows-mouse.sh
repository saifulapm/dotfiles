#!/usr/bin/env bash
# Tailscale, Accounts, DNS, Pass and the cheat sheet by mouse: a click on a row does what Enter does on it, and a click on a key chip does what its key does.
{
source "$(dirname "$0")/lib.sh"
source "$(dirname "$0")/pointer.bash"

cleanup() {
  pointer_stop
  gpgconf --kill gpg-agent 2>/dev/null
}
clip() { timeout 1 wl-paste -n 2>/dev/null; }

# Tailscale lists the fake's rows: iphone, mini, nuc, then the offline two.
ts_state() { timeout 0.5 dots-call tailscale state 2>/dev/null; }
ts_is() { ts_state | jq -e "$@" >/dev/null 2>&1; }
niri msg action spawn -- dots-call tailscale toggle
until_ok 3000 ts_is '.open and .listed and .settled and .keyboard'
check "Tailscale lists mini second ($(ts_state | jq -c '[.rows[].name]'))" ts_is '.rows[1].name == "mini" and .selected == 0'
click_box tailscale-row:1
until_ok 3000 bash -c '[ "$(timeout 1 wl-paste -n 2>/dev/null)" = 100.72.40.9 ]'
check "a click on mini's row copies its address, as Enter does ($(clip))" test "$(clip)" = 100.72.40.9
until_ok 2000 ts_is '.open == false'
check "and closes the card" ts_is '.open == false'

# Accounts: main is active; a click on work's row uses it, as Enter does.
mkdir -p "$XDG_STATE_HOME/dots/claude-accounts/work"
reg=$XDG_STATE_HOME/dots/claude-accounts.json
cat >"$reg" <<EOF
{ "active": "main",
  "accounts": [
    { "id": "main", "label": "main", "home": "$HOME/.claude", "email": "a@b.c", "plan": "max" },
    { "id": "work", "label": "work", "home": "$XDG_STATE_HOME/dots/claude-accounts/work", "email": "x@y.z", "plan": "pro" } ] }
EOF
acc_state() { timeout 0.5 dots-call accounts state 2>/dev/null; }
acc_is() { acc_state | jq -e "$@" >/dev/null 2>&1; }
niri msg action spawn -- dots-call accounts toggle
until_ok 3000 acc_is '.open and .settled and .keyboard'
until_ok 6000 acc_is '.busy == false and (.accounts | length) == 2'
check "Accounts opens with the cursor on main" acc_is '.selected == "account:main"'
click_box accounts-row:account:work
until_ok 5000 test "$(jq -r .active "$reg")" = work
check "a click on work's row makes it the active account, as Enter does ($(jq -r .active "$reg"))" test "$(jq -r .active "$reg")" = work
niri msg action spawn -- dots-call accounts toggle
until_ok 3000 acc_is '.drawing == false'

# DNS: Enter runs nothing on a device, so a click moves the cursor there; a group's head is named by its place, since it has no key.
dns_state() { timeout 0.5 dots-call dns state 2>/dev/null; }
dns_is() { dns_state | jq -e "$@" >/dev/null 2>&1; }
niri msg action spawn -- dots-call dns toggle
until_ok 3000 dns_is '.open and .settled and .keyboard'
until_ok 3000 dns_is '(.rows | length) == 8'
check "DNS opens with the cursor on the first device" dns_is '.cursor == "carried:dev00iphone"'
click_box dns-row:carried:dev00ipad
until_ok 2000 dns_is '.cursor == "carried:dev00ipad"'
check "a click on the iPad's row moves the cursor there and its pane shows ($(dns_state | jq -c '[.cursor, .pane.name]'))" dns_is '.cursor == "carried:dev00ipad" and .pane.name == "iPad"'
has_box() { shell_spot "$1" >/dev/null; }
check "the first group's head draws a click area" has_box dns-row:0
click_box dns-row:0
sleep 0.3
check "a click on a group's head moves nothing" dns_is '.cursor == "carried:dev00ipad"'
wtype -k Escape
until_ok 3000 dns_is '.drawing == false'

# Pass: a store of three entries in this session's scratch GNUPGHOME, as tests/dev/pass.sh makes it.
: "${PASSWORD_STORE_DIR:?}" "${GNUPGHOME:?}"
mkdir -p -m 700 "$GNUPGHOME"
passphrase=dots-test-phrase
echo "pinentry-program $repo/bin/dots-pinentry" >"$GNUPGHOME/gpg-agent.conf"
gpg --batch --pinentry-mode loopback --passphrase "$passphrase" --quick-gen-key 'Dots Test <dots@test>' default default never 2>/dev/null
echo warm | gpg --batch -e -r dots@test 2>/dev/null | gpg --batch --pinentry-mode loopback --passphrase "$passphrase" -d >/dev/null 2>&1
pass init dots@test >/dev/null
for e in web/github.com web/gitlab.com mail/icloud; do printf '%s\n' "secret-$e" | pass insert -e "$e" >/dev/null; done
pass_state() { timeout 0.5 dots-call pass state 2>/dev/null; }
pass_is() { pass_state | jq -e "$@" >/dev/null 2>&1; }
niri msg action spawn -- dots-call pass toggle
until_ok 5000 pass_is '.open and (.rows | length) == 3'
second=$(pass_state | jq -r '.rows[1].name')
click_box pass-row:1
until_ok 8000 bash -c "[ \"\$(timeout 1 wl-paste -n 2>/dev/null)\" = 'secret-$second' ]"
check "a click on Pass's second row ($second) copies its password, as Enter does" test "$(clip)" = "secret-$second"
check "and Pass closed" pass_is '.open | not'

# The cheat sheet's chips: / focuses the filter, esc closes.
sheet_state() { timeout 0.5 qs ipc call cheatsheet state 2>/dev/null; }
sheet_is() { sheet_state | jq -e "$@" >/dev/null 2>&1; }
niri msg action spawn -- dots-call cheatsheet toggle
until_ok 3000 sheet_is '.open and .settled'
click_box cheatsheet-key:0
wtype mute
until_ok 2000 sheet_is '.query == "mute"'
check "a click on the cheat sheet's / chip focuses the filter, so typing filters ($(sheet_state | jq -c .query))" sheet_is '.query == "mute"'
click_box cheatsheet-key:1
until_ok 2000 sheet_is '.open == false'
check "a click on its esc chip closes it" sheet_is '.open == false'

exit "$fails"
}
