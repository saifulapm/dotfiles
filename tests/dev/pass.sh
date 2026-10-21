#!/usr/bin/env bash
# Mod+P finds an entry by subsequence and copies its password out of the clipboard history, cleared 45 s later; o copies its OTP code.
{
source "$(dirname "$0")/lib.sh"

cleanup() { gpgconf --kill gpg-agent 2>/dev/null; }
# bin/dots-dev points the store and the keyring into its temp dir, so nothing here reaches ~/.password-store or ~/.gnupg.
: "${PASSWORD_STORE_DIR:?}" "${GNUPGHOME:?}"
mkdir -p -m 700 "$GNUPGHOME"
password='hunter2-correct-horse' secret=JBSWY3DPEHPK3PXP
gpg --batch --pinentry-mode loopback --passphrase '' --quick-gen-key 'Dots Test <dots@test>' default default never 2>/dev/null
pass init dots@test >/dev/null
for e in web/github.com web/gitlab.com mail/icloud; do printf '%s\n' "$password-$e" | pass insert -e "$e" >/dev/null; done
printf '%s\n' "$password" | pass insert -f -e web/github.com >/dev/null
printf 'otpauth://totp/GitHub:saiful?secret=%s&issuer=GitHub\n' "$secret" | pass otp append -f web/github.com >/dev/null
echo web/github.com >"$XDG_STATE_HOME/dots/pass-otp"

pass_state() { timeout 0.5 dots-call pass state 2>/dev/null; }
state_is() { pass_state | jq -e "$1" >/dev/null; }
island_text() { timeout 0.5 qs ipc call island state 2>/dev/null | jq -r .text; }
clip() { timeout 1 wl-paste -n 2>/dev/null; }

check "before Mod+P the surface is not loaded" state_is '.loaded == false'
niri msg action spawn -- dots-call pass toggle
until_ok 3000 state_is '.open and .listed and .settled and .keyboard'
check "Mod+P opens Pass listing the store ($(pass_state | jq -c '[.rows[].name]'))" state_is '.open and (.rows | map(.name) | sort) == ["mail/icloud", "web/github.com", "web/gitlab.com"]'
check "only the entry with a TOTP secret carries the OTP tag" state_is '[.rows[] | select(.otp) | .name] == ["web/github.com"]'

wtype ghb
until_ok 2000 state_is '.query == "ghb"'
check "ghb leaves one row, web/github.com, and the count says 1 ($(pass_state | jq -c '[.count, .rows[0]]'))" state_is '.count == 1 and .rows[0].name == "web/github.com" and .countText == "1 FOUND"'
check "its matched letters are underlined" state_is '.rows[0].underlined == "ghb"'

wtype -k Return
until_ok 5000 bash -c "[ \"\$(timeout 1 wl-paste -n 2>/dev/null)\" = '$password' ]"
check "Enter puts the password on the clipboard" test "$(clip)" = "$password"
copied_at=$(now_ms)
history_count() { cliphist -db-path "$XDG_STATE_HOME/dots/clips.db" list 2>/dev/null | grep -cF "$password"; }
sleep 0.5
check "cliphist keeps no copy of it ($(history_count))" test "$(history_count)" = 0
until_ok 3000 bash -c 'timeout 0.5 qs ipc call island state 2>/dev/null | jq -e ".text | test(\"Copied\")" >/dev/null'
check "the island says it was copied ($(island_text))" bash -c '[ "$(timeout 0.5 qs ipc call island state | jq -r .text)" = "Copied · clears in 45s" ]'
check "Pass closed" state_is '.open | not'
check "and the next entry used comes first: the list is recent first" bash -c '[ "$(dots-pass list | head -1 | cut -f1)" = web/github.com ]'

# o on the cursor row copies the code oathtool gives for the same secret.
niri msg action spawn -- dots-call pass toggle
until_ok 3000 state_is '.open and .listed and .settled'
wtype -k Tab
until_ok 2000 state_is '.focus == "list"'
wtype o
code_ok() { local c; c=$(clip); [[ $c =~ ^[0-9]{6}$ ]] && { [ "$c" = "$(oathtool --totp -b "$secret")" ] || [ "$c" = "$(oathtool --totp -b -N '30 seconds ago' "$secret")" ]; }; }
until_ok 5000 code_ok
check "o puts the entry's 6-digit OTP code on the clipboard ($(clip))" code_ok
until_ok 3000 bash -c 'timeout 0.5 qs ipc call island state 2>/dev/null | jq -e ".text == \"OTP copied · clears in 45s\"" >/dev/null'
check "and the island says the OTP was copied" bash -c '[ "$(timeout 0.5 qs ipc call island state | jq -r .text)" = "OTP copied · clears in 45s" ]'

# A copy of the password again, then 45 s: the clipboard is empty.
niri msg action spawn -- dots-call pass toggle
until_ok 3000 state_is '.open and .listed and .settled'
wtype ghb
until_ok 2000 state_is '.count == 1'
wtype -k Return
until_ok 5000 bash -c "[ \"\$(timeout 1 wl-paste -n 2>/dev/null)\" = '$password' ]"
copied_at=$(now_ms)
until_ok 50000 bash -c '[ -z "$(timeout 1 wl-paste -n 2>/dev/null)" ]'
check "45 s after Enter wl-paste prints nothing ($(($(now_ms) - copied_at)) ms)" bash -c "[ -z \"\$(timeout 1 wl-paste -n 2>/dev/null)\" ] && [ $(($(now_ms) - copied_at)) -ge 44000 ]"

# Each theme draws the board's key strip; the list unloads 30 s after it closes.
status_theme() { shell_status | jq -e --arg t "$1" '.theme == $t' >/dev/null; }
in_theme() { "$repo/bin/dots" theme "$1" >/dev/null; until_ok 2000 status_theme "$1"; }
for t in "artboard|↵ copy · o otp · s show · n new · e edit · d delete · q qr · esc" "blueprint|[↵] COPY · [O] OTP · [S] SHOW · [N] NEW · [E] EDIT · [D] DELETE · [Q] QR · [ESC]" "paper|↵ COPY · O OTP · S SHOW · N NEW · E EDIT · D DELETE · Q QR · ESC"; do
  IFS='|' read -r name hint <<<"$t"
  in_theme "$name"
  niri msg action spawn -- dots-call pass toggle
  until_ok 3000 state_is '.open and .settled'
  check "$name: the key strip reads $hint ($(pass_state | jq -c .hint))" state_is ".hint == \"$hint\""
  wtype -k Escape
  until_ok 3000 state_is '.drawing == false'
done
until_ok 33000 state_is '.loaded == false'
check "Pass unloads 30 s after it closes" state_is '.loaded == false'

exit $((fails > 0))
}
