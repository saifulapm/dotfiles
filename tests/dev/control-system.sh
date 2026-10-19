#!/usr/bin/env bash
# Control's Power asks for y before a reboot, Display steps a fake backlight, and Route flips a fake workflow route and Do Not Disturb.
{
fake=$(mktemp -d)
fake_log=$fake/argv
cat >"$fake/brightnessctl" <<EOF2
#!/usr/bin/env bash
echo "\$*" >>"$fake_log"
echo "fake-bl,backlight,62,62%,100"
EOF2
chmod +x "$fake/brightnessctl"
# bin/dots-dev hands this PATH to the shell, so the shell runs the fake and never the real backlight.
export PATH=$fake:$PATH
source "$(dirname "$0")/lib.sh"
cleanup() { rm -rf "$fake"; }

control_state() { timeout 0.5 qs ipc call control state 2>/dev/null; }
state_is() { control_state | jq -e "$@" >/dev/null 2>&1; }
mod_c() { niri msg action spawn -- qs ipc call control toggle; }
section_is() { state_is --arg s "$1" '.open and .section == $s'; }
# Presses j or k until the row titled $1 is selected.
select_row() {
  local i n
  i=$(control_state | jq --arg t "$1" '.rows | index($t)')
  [ -n "$i" ] && [ "$i" != null ] || return 1
  for n in 1 2 3 4 5 6 7 8 9 10; do
    state_is --argjson i "$i" '.selected == $i' && return 0
    if state_is --argjson i "$i" '.selected < $i'; then wtype j; else wtype k; fi
    sleep 0.1
  done
  return 1
}
# One Tab at a time, each waiting for the section to move, so a late press never overshoots.
section_not() { ! section_is "$1"; }
tab_to() {
  local n s
  until_ok 3000 state_is '.keyboard' || return 1
  for n in 1 2 3 4 5 6; do
    section_is "$1" && return 0
    s=$(control_state | jq -r .section)
    wtype -k Tab
    until_ok 2000 section_not "$s" || return 1
  done
  section_is "$1"
}

until_ok 5000 shell_status >/dev/null
check "the shell runs the fake workflow" test -x "$DOTS_WORKFLOW"

mod_c
until_ok 3000 section_is audio
tab_to power
check "Tab reaches power" section_is power
check "Power lists the profile and the session actions" state_is '.rows as $r | ["Profile", "Lock", "Log out", "Reboot", "Power off"] | all(. as $t | $r | index($t))'
select_row Reboot
wtype -k Return
until_ok 2000 state_is '.confirming == "reboot"'
check "Enter on Reboot asks for y and runs nothing" state_is '.confirming == "reboot"'
wtype n
until_ok 2000 state_is '.confirming == ""'
check "any other key cancels the confirm" state_is '.confirming == ""'

tab_to display
until_ok 2000 state_is '.rows | index("fake-bl")'
check "Display lists the fake backlight" state_is '.rows | index("fake-bl")'
select_row fake-bl
wtype l
stepped() { grep -qx -- '-m -d fake-bl set 5%+' "$fake_log" 2>/dev/null; }
until_ok 2000 stepped
check "l steps it by 5%+ through brightnessctl" stepped

tab_to route
until_ok 2000 state_is '.route == "device"'
check "Route reads device from workflow route" state_is '.route == "device"'
select_row "Questions ring on"
wtype -k Return
until_ok 2000 state_is '.route == "phone"'
check "Enter switches the route to phone" bash -c "state() { timeout 0.5 qs ipc call control state; }; state | jq -e '.route == \"phone\"' >/dev/null && [ \"\$(cat $DOTS_DEV_DIR/route)\" = phone ]"
wtype -k Return
until_ok 2000 state_is '.route == "device"'
check "Enter again switches it back to device" state_is '.route == "device"'
select_row "Do Not Disturb"
wtype -k Return
dnd() { timeout 0.5 qs ipc call notifs state 2>/dev/null | jq -e ".dnd == $1" >/dev/null; }
until_ok 2000 dnd true
check "Enter on Do Not Disturb turns it on" dnd true
wtype -k Return
until_ok 2000 dnd false
check "and Enter again turns it off" dnd false
wtype -k Escape

exit $((fails > 0))
}
