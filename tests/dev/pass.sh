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
# pass commits each change, and dots-pass pushes it to this bare remote.
remote=$DOTS_DEV_DIR/store-remote.git
git init -q --bare "$remote"
pass git init >/dev/null
pass git remote add origin "$remote"
pass git push -q -u origin HEAD 2>/dev/null

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

# s shows the password on its row for 10 s.
niri msg action spawn -- dots-call pass toggle
until_ok 3000 state_is '.open and .listed and .settled'
wtype ghb
until_ok 2000 state_is '.count == 1'
wtype -k Tab
until_ok 2000 state_is '.focus == "list"'
wtype s
until_ok 5000 state_is '.revealed != null'
check "s shows the password in place of the name, tagged 10s ($(pass_state | jq -c '.revealed | .tag'))" state_is ".revealed.text == \"$password\" and .revealed.tag == \"10s\""
shown_at=$(now_ms)
until_ok 12000 state_is '.revealed == null'
check "10 s later the row shows the name only ($(($(now_ms) - shown_at)) ms)" bash -c "timeout 0.5 dots-call pass state | jq -e '.revealed == null and .rows[0].name == \"web/github.com\"' >/dev/null && [ $(($(now_ms) - shown_at)) -ge 9000 ]"

# n makes a new entry with a generated 24-character password; h and l change its length.
wtype n
until_ok 3000 state_is '.mode == "new" and .newEntry.length == 24'
check "n opens the new-entry card with a 24-character password" state_is '.newEntry.length == 24 and .newEntry.focus == "path"'
wtype web/github.com
until_ok 2000 state_is '.newEntry.path == "web/github.com"'
check "a path that exists is tagged exists ($(pass_state | jq -c .newEntry.tag))" state_is '.newEntry.tag | ascii_downcase == "exists"'
wtype -k Return
sleep 1
check "and Enter does not overwrite it" bash -c "[ \"\$(pass show web/github.com | head -1)\" = '$password' ] && timeout 0.5 dots-call pass state | jq -e '.mode == \"new\"' >/dev/null"
wtype -k Escape
until_ok 2000 state_is '.mode == "list"'
wtype n
until_ok 3000 state_is '.mode == "new" and .newEntry.length == 24'
wtype web/linear.app
until_ok 2000 state_is '.newEntry.path == "web/linear.app"'
check "a new path is tagged new ($(pass_state | jq -c .newEntry.tag))" state_is '.newEntry.tag | ascii_downcase == "new"'
wtype -k Tab
until_ok 2000 state_is '.newEntry.focus == "length"'
wtype l
until_ok 3000 state_is '.newEntry.length == 25'
check "l lengthens the password to 25" state_is '.newEntry.length == 25'
wtype h
until_ok 3000 state_is '.newEntry.length == 24'
check "h shortens it back to 24" state_is '.newEntry.length == 24'
wtype -k Return
saved() { [ "$(pass show web/linear.app 2>/dev/null | head -1 | tr -d '\n' | wc -c)" = 24 ]; }
until_ok 8000 saved
check "Enter saves it: pass show web/linear.app prints a 24-character password" saved
pushed() { git -C "$remote" log -1 --format=%s | grep -qF "$1"; }
until_ok 5000 pushed "Add given password for web/linear.app"
check "and the store's remote has the commit ($(git -C "$remote" log -1 --format=%s))" pushed web/linear.app

# d asks on one line under the list, and y deletes.
until_ok 3000 state_is '.mode == "list" and .listed'
wtype -k slash
wtype -M ctrl a -m ctrl
until_ok 2000 state_is '.focus == "query"'
wtype linear
until_ok 2000 state_is '.count == 1 and .rows[0].name == "web/linear.app"'
wtype -k Tab
until_ok 2000 state_is '.focus == "list"'
wtype d
until_ok 2000 state_is '.mode == "delete"'
check "d asks on one line ($(pass_state | jq -c .deleteLine))" state_is '.deleteLine == "Delete web/linear.app?  Y YES · N NO"'
wtype y
gone() { ! pass ls 2>/dev/null | grep -q linear.app; }
until_ok 8000 gone
check "y deletes it: pass ls no longer lists it" gone
until_ok 5000 pushed "Remove web/linear.app"
check "and the store's remote's last commit names it ($(git -C "$remote" log -1 --format=%s))" pushed "web/linear.app"
wtype -k Escape
until_ok 3000 state_is '.drawing == false'

# q reads an otpauth QR from the clipboard image: the card names it without its secret, and Enter on an entry saves it there.
qr_secret=KRSXG5CTMVRXEZLUKN2XAZLSKNSWG4TF
qrencode -o "$DOTS_DEV_DIR/qr.png" "otpauth://totp/GitHub:saiful?secret=$qr_secret&issuer=GitHub"
wl-copy --type image/png <"$DOTS_DEV_DIR/qr.png"
niri msg action spawn -- dots-call pass toggle
until_ok 3000 state_is '.open and .listed and .settled'
wtype -k Tab
until_ok 2000 state_is '.focus == "list"'
wtype q
until_ok 5000 state_is '.mode == "qr"'
check "q names the code: GitHub, saiful, TOTP · 6 digits · 30s ($(pass_state | jq -c .qr))" state_is '.qr == {"issuer": "GitHub", "account": "saiful", "meta": "TOTP · 6 digits · 30s", "question": "Save to which entry?"}'
check "no surface state holds the secret" bash -c "! timeout 0.5 dots-call pass state | grep -qF '$qr_secret'"
wtype github.com
until_ok 2000 state_is '.count == 1 and .rows[0].name == "web/github.com"'
wtype -k Return
qr_code_ok() { local c; c=$(pass otp web/github.com 2>/dev/null); [[ $c =~ ^[0-9]{6}$ ]] && { [ "$c" = "$(oathtool --totp -b "$qr_secret")" ] || [ "$c" = "$(oathtool --totp -b -N '30 seconds ago' "$qr_secret")" ]; }; }
until_ok 8000 qr_code_ok
check "Enter on web/github.com saves it: pass otp web/github.com prints the new code ($(pass otp web/github.com 2>/dev/null))" qr_code_ok
check "and keeps the entry's password" bash -c "[ \"\$(pass show web/github.com | head -1)\" = '$password' ]"
check "the shell's journal never holds the secret" bash -c "! journalctl --user -u '$DOTS_DEV_UNIT' --no-pager -o cat | grep -qF '$qr_secret'"
until_ok 3000 bash -c 'timeout 0.5 qs ipc call island state 2>/dev/null | jq -e ".text == \"OTP saved · web/github.com\"" >/dev/null'
check "the island says the code was saved ($(island_text))" bash -c '[ "$(timeout 0.5 qs ipc call island state | jq -r .text)" = "OTP saved · web/github.com" ]'
wtype -k Escape
until_ok 3000 state_is '.drawing == false'

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
