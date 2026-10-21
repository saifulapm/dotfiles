#!/usr/bin/env bash
# gpg asks for its passphrase on the shell's card: a real agent in a scratch home runs bin/dots-pinentry, and pass show waits on the card.
{
source "$(dirname "$0")/lib.sh"

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
  pass show web/github.com >"$out/$1.out" 2>"$out/$1.err" &
  pid=$!
}
exited() { ! kill -0 "$1" 2>/dev/null; }
rc_of() {
  wait "$1"
  echo $?
}

check "before any request the card is not loaded" state_is '.loaded == false'

# A cold agent asks: the card opens over the launcher's dim with gpg's description.
show_bg first
until_ok 8000 state_is '.open and .settled'
check "pass show with a cold agent opens the card with gpg's description ($(pin_state | jq -c '.description[0:20]'))" state_is '.open and .kind == "passphrase" and (.description | startswith("Please enter the pas"))'
check "the card holds the keyboard" focus_is Exclusive
check "the field is masked" state_is '.masked'

# A wrong passphrase comes back from gpg as a retry on the same pinentry: the card reopens with the error and an empty field.
wtype 'wrong one'
until_ok 2000 state_is '.field == 9'
wtype -k Return
until_ok 8000 state_is '.open and .error != ""'
check "a wrong passphrase reopens the card with the board's error line ($(pin_state | jq -c .error))" state_is '.open and (.error | test("^Bad passphrase · try 2 of 3$"))'
check "and its field is empty" state_is '.field == 0'

wtype "$passphrase"
until_ok 2000 state_is ".field == ${#passphrase}"
wtype -k Return
until_ok 8000 exited "$pid"
rc=$(rc_of "$pid")
check "the right passphrase, with % and non-ASCII in it, decrypts: pass show exits 0 (rc $rc)" test "$rc" = 0
check "and prints the password" grep -qxF "$password" "$out/first.out"
until_ok 3000 state_is '.open | not'
check "the card closes and gives the keyboard back" focus_is None

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

# While the screen is locked, the stub cancels before any card opens.
marker=$XDG_STATE_HOME/dots/locked
date +%s >"$marker"
gpgconf --kill gpg-agent
t0=$(now_ms)
show_bg locked
until_ok 4000 exited "$pid"
rc=$(rc_of "$pid") ms=$(($(now_ms) - t0))
check "with the lock marker down pass show exits non-zero in under 2 s (rc $rc, $ms ms)" bash -c "[ $rc != 0 ] && [ $ms -lt 2000 ]"
check "and no card opened" state_is '.open | not'
: >"$marker"

# Two requests at once: the second waits behind the first, and neither hangs. The prompt is not gpg's Passphrase:, so the only passphrase on the card is its heading.
ask() { printf 'SETDESC %s\nSETPROMPT Secret:\nGETPIN\nBYE\n' "$1" | "$repo/bin/dots-pinentry" >"$out/$1.assuan" & echo $!; }
a=$(ask first-request)
until_ok 3000 state_is '.open and .description == "first-request"'
b=$(ask second-request)
until_ok 3000 state_is '.waiting == 1'
check "a second request waits while the first shows" state_is '.open and .description == "first-request" and .waiting == 1'
wtype one
wtype -k Return
until_ok 3000 state_is '.open and .description == "second-request" and .waiting == 0'
check "answering the first shows the second" state_is '.open and .description == "second-request"'
wtype -k Escape
until_ok 3000 exited "$b"
check "the first got its passphrase and the second its cancel" bash -c "grep -qx 'D one' '$out/first-request.assuan' && grep -qx 'ERR 83886179 Operation cancelled' '$out/second-request.assuan'"

# gpg's error is the agent's text: one too long for the card is cut short inside it.
long=$(printf 'A%.0s' $(seq 200))
printf 'SETDESC long error\nSETERROR %s\nGETPIN\nBYE\n' "$long" | "$repo/bin/dots-pinentry" >/dev/null &
p=$!
until_ok 3000 state_is '.open and .settled and .error != ""'
check "a 200-character error is cut short inside the card ($(pin_state | jq -c '[.errorTruncated, .errorRight, (.cardBox.x + .cardBox.w)]'))" state_is '.errorTruncated and .errorRight <= .cardBox.x + .cardBox.w - 19'
wtype -k Escape
until_ok 3000 exited "$p"
until_ok 3000 state_is '.drawing == false'

# Each theme draws the card with its own heading and key strip, read off the screen.
read -r ox oy < <(niri msg -j outputs | jq -r 'first(.[]).logical | "\(.x) \(.y)"')
status_theme() { shell_status | jq -e --arg t "$1" '.theme == $t' >/dev/null; }
in_theme() { "$repo/bin/dots" theme "$1" >/dev/null; until_ok 2000 status_theme "$1"; }
box_of() { pin_state | jq -r --argjson ox "$ox" --argjson oy "$oy" --arg k "$1" '.[$k] | "\(.x + $ox - 4 | round),\(.y + $oy - 4 | round) \(.w + 8 | round)x\(.h + 8 | round)"'; }
# Paper's chip is light on ink, which tesseract reads only negated.
negated() {
  node -e '
    const b = require("fs").readFileSync(0);
    const head = b.toString("latin1").match(/^P6\s+\d+\s+\d+\s+\d+\s/)[0].length;
    for (let i = head; i < b.length; i++) b[i] = 255 - b[i];
    process.stdout.write(b);
  '
}
seen_text() {
  grim -s 2 -g "$(box_of cardBox)" - | tesseract stdin - 2>/dev/null
  grim -s 4 -t ppm -g "$(box_of headingBox)" - | negated | tesseract stdin - --psm 7 2>/dev/null
}
for t in "artboard|Passphrase|↵ unlock  esc cancel" "blueprint|GPG // PASSPHRASE|[↵] UNLOCK  [ESC] CANCEL" "paper|PASSPHRASE|↵ UNLOCK  ESC CANCEL"; do
  IFS='|' read -r name heading hint <<<"$t"
  in_theme "$name"
  p=$(ask "Unlock the $name key")
  until_ok 3000 state_is '.open and .settled'
  check "$name: the heading reads $heading and the strip $hint ($(pin_state | jq -c '[.heading, .hint]'))" state_is ".heading == \"$heading\" and .hint == \"$hint\""
  text=$(seen_text | tr -s ' \n' ' ')
  check "$name: the screen shows the heading (tesseract read: $text)" grep -qF "$heading" <<<"$text"
  wtype -k Escape
  until_ok 3000 exited "$p"
  until_ok 3000 state_is '.drawing == false'
done

# A closed card unloads 30 s after it stops drawing.
check "the card is still loaded right after it closes" state_is '.loaded'
until_ok 33000 state_is '.loaded == false'
check "and unloaded 30 s later" state_is '.loaded == false'

exit $((fails > 0))
}
