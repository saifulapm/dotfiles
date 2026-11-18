#!/usr/bin/env bash
# gpg asks for its passphrase on the shell's prompt: a real agent in a scratch home runs bin/dots-pinentry, and pass show waits on the prompt.
{
source "$(dirname "$0")/lib.sh"
# A prompt ignores Enter for its first half second (29PTQZ0V), so each Enter waits that out.
enter() {
  sleep 0.5
  wtype -k Return
}

gnupg=$(mktemp -d) store=$(mktemp -d) out=$(mktemp -d)
cleanup() {
  GNUPGHOME=$gnupg gpgconf --kill gpg-agent 2>/dev/null
  rm -rf "$gnupg" "$store" "$out"
}
export GNUPGHOME=$gnupg PASSWORD_STORE_DIR=$store
unset PINENTRY_USER_DATA GPG_TTY
# % and non-ASCII must reach gpg as typed, so the passphrase holds an escape that would read as A if passed raw.
passphrase='ünï %41 phrase' password='hunter2-correct-horse'
echo "pinentry-program $repo/bin/dots-pinentry" >"$gnupg/gpg-agent.conf"
gpg --batch --pinentry-mode loopback --passphrase "$passphrase" --quick-gen-key 'Dots Test <dots@test>' ed25519 cert,sign never 2>/dev/null
fpr=$(gpg --list-keys --with-colons dots@test | awk -F: '$1 == "fpr" { print $10; exit }')
gpg --batch --pinentry-mode loopback --passphrase "$passphrase" --quick-add-key "$fpr" cv25519 encr never 2>/dev/null
pass init dots@test >/dev/null
printf '%s\n' "$password" | pass insert -e web/github.com >/dev/null
gpgconf --kill gpg-agent

pin_state() { timeout 0.5 dots-call pinentry state 2>/dev/null; }
state_is() { pin_state | jq -e "$1" >/dev/null; }
focus_is() { niri msg -j layers | jq -e --arg k "$1" 'any(.[]; .namespace == "dots-surfaces" and .keyboard_interactivity == $k)' >/dev/null; }
# Not in a subshell, so its pid stays this shell's child for wait.
show_bg() {
  pass show web/github.com >"$out/$1.out" 2>"$out/$1.err" 9>&- &
  pid=$!
}
exited() { ! kill -0 "$1" 2>/dev/null; }
rc_of() {
  wait "$1"
  echo $?
}

check "before any request the prompt is not loaded" state_is '.loaded == false'

# A cold agent asks: the prompt takes the island with gpg's description.
show_bg first
until_ok 8000 state_is '.open and .settled'
check "pass show with a cold agent opens the prompt with gpg's description ($(pin_state | jq -c '.description[0:20]'))" state_is '.open and .kind == "passphrase" and (.description | startswith("Please enter the pas"))'
check "the prompt holds the keyboard" focus_is Exclusive
check "the field is masked" state_is '.drawnField.secret'

# A wrong passphrase comes back from gpg as a retry on the same pinentry: the prompt shows again with the error and an empty field.
wtype 'wrong one'
until_ok 2000 state_is '.field == 9'
enter
until_ok 8000 state_is '.open and .error != ""'
check "a wrong passphrase shows the prompt again with the board's error line ($(pin_state | jq -c .error))" state_is '.open and (.error | test("^Bad passphrase · try 2 of 3$"))'
check "and its field is empty" state_is '.field == 0'

wtype "$passphrase"
until_ok 2000 state_is ".field == ${#passphrase}"
enter
until_ok 8000 exited "$pid"
rc=$(rc_of "$pid")
check "the right passphrase, with % and non-ASCII in it, decrypts: pass show exits 0 (rc $rc)" test "$rc" = 0
check "and prints the password" grep -qxF "$password" "$out/first.out"
until_ok 3000 state_is '.open | not'
check "the prompt closes and gives the keyboard back" focus_is None

# Esc reaches gpg as a cancel, so the terminal gets gpg's error instead of hanging.
gpgconf --kill gpg-agent
show_bg esc
until_ok 8000 state_is '.open and .settled'
wtype -k Escape
until_ok 8000 exited "$pid"
rc=$(rc_of "$pid")
check "Esc makes pass show exit non-zero (rc $rc) with gpg's Operation cancelled" bash -c "[ $rc != 0 ] && grep -q 'Operation cancelled' '$out/esc.err'"

unlogged() { ! journalctl --user -u "$DOTS_DEV_UNIT" --no-pager -o cat 2>/dev/null | grep -qF -e "$passphrase" -e 'wrong one'; }
check "the shell's journal holds no typed passphrase" unlogged

# While the screen is locked, the stub cancels before any prompt opens.
marker=$XDG_STATE_HOME/dots/locked
date +%s >"$marker"
gpgconf --kill gpg-agent
t0=$(now_ms)
show_bg locked
until_ok 4000 exited "$pid"
rc=$(rc_of "$pid") ms=$(($(now_ms) - t0))
check "with the lock marker down pass show exits non-zero in under 2 s (rc $rc, $ms ms)" bash -c "[ $rc != 0 ] && [ $ms -lt 2000 ]"
check "and no prompt opened" state_is '.open | not'
: >"$marker"

# Two requests at once: the second waits behind the first, and neither hangs. The prompt is not gpg's Passphrase:, so the prompt's own words do not match.
ask() { printf 'SETDESC %s\nSETPROMPT Secret:\nGETPIN\nBYE\n' "$1" | "$repo/bin/dots-pinentry" >"$out/$1.assuan" 9>&- & echo $!; }
a=$(ask first-request)
until_ok 3000 state_is '.open and .description == "first-request"'
b=$(ask second-request)
until_ok 3000 state_is '.waiting == 1'
check "a second request waits while the first shows" state_is '.open and .description == "first-request" and .waiting == 1'
wtype one
enter
until_ok 3000 state_is '.open and .description == "second-request" and .waiting == 0'
check "answering the first shows the second" state_is '.open and .description == "second-request"'
wtype -k Escape
until_ok 3000 exited "$b"
check "the first got its passphrase and the second its cancel" bash -c "grep -qx 'D one' '$out/first-request.assuan' && grep -qx 'ERR 83886179 Operation cancelled' '$out/second-request.assuan'"

# gpg's error is the agent's text: one too long for the prompt is cut short, and the prompt keeps its width.
long=$(printf 'A%.0s' $(seq 200))
printf 'SETDESC long error\nSETERROR %s\nGETPIN\nBYE\n' "$long" 9>&- | "$repo/bin/dots-pinentry" >/dev/null 9>&- &
p=$!
until_ok 3000 state_is '.open and .settled and .error != ""'
check "a 200-character error leaves the prompt 520 px wide ($(pin_state | jq -c '[.width, (.error | length)]'))" state_is '.width == 520 and (.error | length) == 200'
wtype -k Escape
until_ok 3000 exited "$p"
until_ok 3000 state_is '.open | not'

# The prompt draws board 7's words and buttons.
p=$(ask "Unlock the key")
until_ok 3000 state_is '.open and .settled'
check "the title reads Passphrase required with Cancel and an inverted Unlock ($(pin_state | jq -c '[.title, .detail, [.buttons[] | .text]]'))" state_is '.title == "Passphrase required" and ([.buttons[] | [.text, .inverted]] == [["Cancel", false], ["Unlock", true]])'
wtype -k Escape
until_ok 3000 exited "$p"
until_ok 3000 state_is '.open | not'

# A closed prompt unloads 30 s after it closes.
check "the prompt is still loaded right after it closes" state_is '.loaded'
until_ok 33000 state_is '.loaded == false'
check "and unloaded 30 s later" state_is '.loaded == false'

exit $((fails > 0))
}
