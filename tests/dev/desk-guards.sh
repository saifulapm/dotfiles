#!/usr/bin/env bash
# An open polkit or pinentry prompt refuses every key and click, --any too, and its field stays empty; once it closes keys go again. A polkit prompt opening after key 5 of a 40-character screen type stops it within 6 keys, and a lock taken after key 10 of screen key Tab 50 stops it within 11, each with its field empty. A prompt opening during mouse click's hit-test, or after gui click's agent-window check, refuses that action too.
{
source "$(dirname "$0")/lib.sh"
unset TMUX

dots_pointer_build || exit 1
scripts=$repo/home/dot_claude/skills/desktop/scripts
screen=$scripts/screen
# pkexec always reaches the live polkitd, so a fake authority on the nested bus asks the nested shell's agent instead.
fake() { busctl --address="$DBUS_SESSION_BUS_ADDRESS" call org.freedesktop.PolicyKit1 /org/freedesktop/PolicyKit1/Authority org.dots.FakePolkit "$@"; }
DBUS_SYSTEM_BUS_ADDRESS=$DBUS_SESSION_BUS_ADDRESS "$repo/bin/dev-fake-polkit" &
fake_pid=$! pin_pid=
cleanup() { kill "$fake_pid" $pin_pid 2>/dev/null; }
until_ok 3000 fake Registered >/dev/null 2>&1
# The agent registers as the shell starts, so the shell restarts once the authority is up.
systemctl --user restart "$DOTS_DEV_UNIT"
until_ok 5000 shell_status >/dev/null
until_ok 6000 at_rest

state_is() { timeout 0.5 dots-call "$1" state 2>/dev/null | jq -e "$2" >/dev/null; }
refused() { [ "$1" = 3 ] && jq -e ". == {refused: \"$3\"}" <<<"$2" >/dev/null; }
typed=$DOTS_DEV_DIR/typed
mkdir -p "$typed"
# A foot whose shell is a raw cat into a file, so every key that reaches it shows there.
raw() { echo "stty raw -echo; exec cat >$typed/$1"; }
read_is() { [ "$(cat "$typed/$1" 2>/dev/null)" = "$2" ]; }
window_of() { niri msg -j windows | jq -r ".[] | select(.app_id == \"$1\") | .id" | sort -n | tail -1; }
has_window() { [ -n "$(window_of "$1")" ]; }
focus_is() { niri msg -j focused-window | jq -e ".id == $1" >/dev/null; }
launch() {
  "$screen" launch foot -c /dev/null -a "$1" sh -c "$(raw "$1")" >/dev/null
  until_ok 5000 has_window "$1"
  until_ok 2000 focus_is "$(window_of "$1")"
}
read -r cx cy < <(niri msg -j focused-output | jq -r '.logical | "\(.x + .width / 2 | floor) \(.y + .height / 2 | floor)"')

launch ours
"$screen" type a >/dev/null
check "before any prompt, screen type a reaches the launched foot" until_ok 2000 read_is ours a

fake Begin s c1 >/dev/null
until_ok 3000 state_is polkit '.open and .settled'
out=$("$screen" type x --any)
rc=$?
check "with the polkit prompt open, screen type x --any exits 3 refusing \"auth prompt\" (got $rc: $out)" refused "$rc" "$out" "auth prompt"
out=$("$scripts/mouse" click "$cx" "$cy" --any)
rc=$?
check "and mouse click --any too (got $rc: $out)" refused "$rc" "$out" "auth prompt"
sleep 0.3
check "and the prompt's field reads empty" state_is polkit '.open and .field == 0'
wtype -k Escape
until_ok 2000 state_is polkit '.open == false'
niri msg action focus-window --id "$(window_of ours)"
until_ok 2000 focus_is "$(window_of ours)"
"$screen" type x >/dev/null
check "once it closes, the same screen type reaches the launched foot again" until_ok 2000 read_is ours ax

# A pinentry card from bin/dots-pinentry, held open by a GETPIN on its stdin.
mkfifo "$DOTS_DEV_DIR/pin.in"
"$repo/bin/dots-pinentry" <"$DOTS_DEV_DIR/pin.in" >"$DOTS_DEV_DIR/pin.out" &
pin_pid=$!
exec 9>"$DOTS_DEV_DIR/pin.in"
echo GETPIN >&9
until_ok 5000 state_is pinentry '.open and .settled'
out=$("$screen" key Return --any)
rc=$?
check "with the pinentry card open, screen key Return --any exits 3 refusing \"auth prompt\" (got $rc: $out)" refused "$rc" "$out" "auth prompt"
out=$("$scripts/mouse" click "$cx" "$cy")
rc=$?
check "and mouse click too (got $rc: $out)" refused "$rc" "$out" "auth prompt"
sleep 0.3
check "and the card's field reads empty" state_is pinentry '.open and .field == 0'
wtype -k Escape
until_ok 2000 state_is pinentry '.open == false'
exec 9>&-
kill "$pin_pid" 2>/dev/null
pin_pid=

# A wtype that, once $1 of its calls match $2, runs $3 before it returns, so the next key of the burst meets it.
shim() {
  mkdir -p "$DOTS_DEV_DIR/shim"
  : >"$DOTS_DEV_DIR/shim.log"
  printf '#!/usr/bin/env bash\n%q "$@" || exit\necho "$*" >>%q\n[ "$(grep -cE %q %q)" = %q ] && { %s; }\nexit 0\n' \
    "$(command -v wtype)" "$DOTS_DEV_DIR/shim.log" "$2" "$DOTS_DEV_DIR/shim.log" "$1" "$3" >"$DOTS_DEV_DIR/shim/wtype"
  chmod +x "$DOTS_DEV_DIR/shim/wtype"
}
count() { grep -cE "$1" "$DOTS_DEV_DIR/shim.log"; }

launch burst
shim 5 '^-- ' "busctl --address='$DBUS_SESSION_BUS_ADDRESS' call org.freedesktop.PolicyKit1 /org/freedesktop/PolicyKit1/Authority org.dots.FakePolkit Begin s c2 >/dev/null; for _ in \$(seq 60); do dots-call polkit state | jq -e .open >/dev/null && break; sleep 0.05; done"
text=abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMN
out=$(PATH=$DOTS_DEV_DIR/shim:$PATH "$screen" type "$text")
rc=$?
check "a polkit prompt opening after key 5 of a 40-character screen type stops it with exit 3 (got $rc: $out)" refused "$rc" "$out" "auth prompt"
sent=$(count '^-- ')
check "at most 6 keys went out ($sent)" bash -c "((5 <= $sent && $sent <= 6))"
sleep 0.3
check "the foot reads only those keys, in order ($(cat "$typed/burst"))" read_is burst "${text:0:sent}"
check "and the prompt's field reads empty" state_is polkit '.open and .field == 0'
wtype -k Escape
until_ok 2000 state_is polkit '.open == false'

launch tabs
shim 10 '^-k Tab$' "dots-call lock lock >/dev/null; for _ in \$(seq 60); do dots-call lock state | jq -e .locked >/dev/null && break; sleep 0.05; done"
out=$(PATH=$DOTS_DEV_DIR/shim:$PATH "$screen" key Tab 50)
rc=$?
check "a lock taken after key 10 of screen key Tab 50 stops it with exit 3 (got $rc: $out)" refused "$rc" "$out" "locked"
sent=$(count '^-k Tab$')
check "at most 11 keys went out ($sent)" bash -c "((10 <= $sent && $sent <= 11))"
check "the lock's field reads empty" state_is lock '.locked and .field == 0'
wtype dots-test-pass
wtype -k Return
until_ok 3000 state_is lock '.locked == false'
tabs_are() { [ "$(tr -cd '\t' <"$typed/tabs" | wc -c)" = "$1" ]; }
check "and the foot reads those $sent tabs" tabs_are "$sent"

# A dots-pointer that opens a polkit prompt as soon as its pick has answered: the prompt lands between mouse's hit-test and its press.
mkdir -p "$DOTS_DEV_DIR/pickshim"
printf '#!/usr/bin/env bash\necho "$*" >>%q\n%q "$@" || exit\ncase " $* " in *" pick "*) %s ;; esac\n' \
  "$DOTS_DEV_DIR/pick.log" "$(command -v dots-pointer)" \
  "busctl --address='$DBUS_SESSION_BUS_ADDRESS' call org.freedesktop.PolicyKit1 /org/freedesktop/PolicyKit1/Authority org.dots.FakePolkit Begin s c3 >/dev/null; for _ in \$(seq 60); do dots-call polkit state | jq -e .open >/dev/null && break; sleep 0.05; done" >"$DOTS_DEV_DIR/pickshim/dots-pointer"
chmod +x "$DOTS_DEV_DIR/pickshim/dots-pointer"
niri msg action fullscreen-window --id "$(window_of tabs)"
sleep 0.5
out=$(PATH=$DOTS_DEV_DIR/pickshim:$PATH "$scripts/mouse" click "$cx" "$cy")
rc=$?
check "a polkit prompt opening during mouse click's hit-test over an agent window refuses it (got $rc: $out)" refused "$rc" "$out" "auth prompt"
check "and no press followed the pick ($(tr '\n' '|' <"$DOTS_DEV_DIR/pick.log"))" bash -c "grep -q pick '$DOTS_DEV_DIR/pick.log' && ! grep -q click '$DOTS_DEV_DIR/pick.log'"
wtype -k Escape
until_ok 2000 state_is polkit '.open == false'

# A dots-call whose second polkit state reads open: gui reads the prompts again after its agent-window check, just before it acts.
mkdir -p "$DOTS_DEV_DIR/callshim"
printf '#!/usr/bin/env bash\nif [ "$*" = "polkit state" ]; then echo x >>%q; [ "$(wc -l <%q)" -ge 2 ] && { echo %q; exit 0; }; fi\nexec %q "$@"\n' \
  "$DOTS_DEV_DIR/polkit.reads" "$DOTS_DEV_DIR/polkit.reads" '{"open":true}' "$(command -v dots-call)" >"$DOTS_DEV_DIR/callshim/dots-call"
chmod +x "$DOTS_DEV_DIR/callshim/dots-call"
"$screen" launch gtk4-widget-factory >/dev/null
until_ok 8000 has_window org.gtk.WidgetFactory4
found() { "$scripts/gui" find gtk4-widget-factory checkbutton >/dev/null 2>&1; }
until_ok 8000 found
# Five check boxes share the name, and GTK4's offer no action, so the click goes to one toggle by its ref.
toggle=$("$scripts/gui" tree gtk4-widget-factory | jq -r '[.nodes[] | select(.role == "toggle button" and .name == "togglebutton")][0].ref')
out=$(PATH=$DOTS_DEV_DIR/callshim:$PATH "$scripts/gui" click gtk4-widget-factory "$toggle")
rc=$?
check "a polkit prompt reading open after gui click's agent-window check refuses it (got $rc: $out)" refused "$rc" "$out" "auth prompt"
check "on its second read of polkit state" test "$(wc -l <"$DOTS_DEV_DIR/polkit.reads")" = 2

exit $((fails > 0))
}
