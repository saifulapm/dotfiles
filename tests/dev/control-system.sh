#!/usr/bin/env bash
# Control's Power page asks again before a reboot, red as Reboot?, and runs it only on a second Enter; Display steps a fake backlight, and Route flips a fake workflow route and draws a failed sync unit in red on one line.
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
mod_c() { niri msg action spawn -- dots-call control toggle; }
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
# Opens Control on a page by name, as Enter on its tile and the power key do.
page_to() {
  timeout 0.5 qs ipc call control section "$1"
  until_ok 3000 section_is "$1" && until_ok 3000 state_is '.keyboard'
}

until_ok 5000 shell_status >/dev/null
check "the shell runs the fake workflow" test -x "$DOTS_WORKFLOW"

# The power key runs dots-call control section power (binds.kdl).
niri msg action spawn -- dots-call control section power
until_ok 3000 section_is power
until_ok 3000 state_is '.keyboard'
check "the power key opens Control on its Power page" section_is power
check "Power lists the profile and the session actions" state_is '.rows as $r | ["Profile", "Lock", "Log out", "Reboot", "Power off"] | all(. as $t | $r | index($t))'
check "its four square actions read Lock, Log out, Reboot and Power off ($(control_state | jq -c .power.actions))" state_is '.power.actions == ["Lock", "Log out", "Reboot", "Power off"]'
# Never a second Enter on Reboot here: the nested shell's systemctl is dev/path's stand-in, and it must stay unasked.
select_row Reboot
# A held Enter repeats; only its first press counts, so it shows Reboot? and never confirms it.
wtype -P Return
sleep 1.2
wtype -p Return
until_ok 2000 state_is '.confirming == "reboot"'
check "a held Enter on Reboot asks once and runs nothing" bash -c "timeout 0.5 qs ipc call control state | jq -e '.confirming == \"reboot\"' >/dev/null && ! [ -s '$DOTS_DEV_DIR/systemctl-power' ]"
wtype -k Escape
until_ok 2000 state_is '.confirming == ""'
wtype -k Return
until_ok 2000 state_is '.confirming == "reboot"'
check "Enter on Reboot asks again and runs nothing" state_is '.confirming == "reboot"'
check "the button turns red and reads Reboot? ($(control_state | jq -c .power.actions))" state_is '.power.actions[2] == "Reboot?"'
wtype -k Escape
until_ok 2000 state_is '.confirming == ""'
check "Esc puts it back and stays on Power" state_is '.confirming == "" and .section == "power" and .power.actions[2] == "Reboot"'
check "nothing asked systemctl to reboot" bash -c "! [ -s '$DOTS_DEV_DIR/systemctl-power' ]"

# The charge limit goes through dev/path's fake UPower, which starts on at 80; only a machine with a threshold has the row.
if compgen -G '/sys/class/power_supply/*/charge_control_end_threshold' >/dev/null; then
  live_limit() { cat /sys/class/power_supply/*/charge_control_end_threshold | head -1; }
  live_before=$(live_limit)
  select_row "Charge limit"
  check "Charge limit reads 80% from UPower" state_is '.chargeLimit == 80'
  wtype -k Return
  until_ok 2000 state_is '.chargeLimit == 0'
  check "Enter turns it off" state_is '.chargeLimit == 0'
  check "through UPower's EnableChargeThreshold" test "$(cat "$DOTS_DEV_DIR/charge-limit")" = false
  wtype -k Return
  until_ok 2000 state_is '.chargeLimit == 80'
  check "and Enter again turns it back on" state_is '.chargeLimit == 80'
  check "the live battery's limit is untouched ($(live_limit))" test "$(live_limit)" = "$live_before"
fi

# Stay awake steps off, 30 min, 1 h, 2 h, off, and the idle steps read the same hold.
awake_in() { state_is --argjson m "$1" '.awakeUntil > 0 and ((.awakeUntil - now * 1000) / 60000 | ceil) == $m'; }
select_row "Stay awake"
check "Stay awake starts off" state_is '.awakeUntil == 0'
wtype -k Return
until_ok 2000 awake_in 30
check "Enter holds it for 30 min" awake_in 30
check "and its 30 min segment is lit ($(control_state | jq -c .power.awake))" state_is '.power.awake == "30 min"'
check "and the idle steps hold off as long" bash -c "timeout 0.5 qs ipc call idle state | jq -e --argjson u $(control_state | jq .awakeUntil) '.awakeUntil == \$u'"
wtype l
until_ok 2000 awake_in 60
check "l steps it to 1 h" awake_in 60
wtype -k Return
until_ok 2000 awake_in 120
wtype -k Return
until_ok 2000 state_is '.awakeUntil == 0'
check "past 2 h it turns off" state_is '.awakeUntil == 0'

page_to display
until_ok 2000 state_is '.rows | index("fake-bl")'
check "Display lists the fake backlight" state_is '.rows | index("fake-bl")'
until_ok 2000 state_is '.rows | index("FAKE-B")'
check "Display lists both fake external displays" state_is '.rows as $r | ["FAKE-A", "FAKE-B"] | all(. as $t | $r | index($t))'
select_row fake-bl
wtype l
stepped() { grep -qx -- '-m -d fake-bl set 5%+' "$fake_log" 2>/dev/null; }
until_ok 2000 stepped
check "l steps it by 5%+ through brightnessctl" stepped
select_row FAKE-A
wtype =
ddc_stepped() { grep -qx -- '-d 1 setvcp 10 + 5' "$DOTS_DEV_DIR/ddcutil-set" 2>/dev/null; }
until_ok 2000 ddc_stepped
check "= on the external FAKE-A raises it one step through ddcutil ($(tail -1 "$DOTS_DEV_DIR/ddcutil-set" 2>/dev/null))" ddc_stepped

page_to route
until_ok 2000 state_is '.route == "device"'
check "Route reads device from workflow route" state_is '.route == "device"'
select_row "Questions ring on"
wtype -k Return
until_ok 2000 state_is '.route == "phone"'
check "Enter switches the route to phone" bash -c "state() { timeout 0.5 qs ipc call control state; }; state | jq -e '.route == \"phone\"' >/dev/null && [ \"\$(cat $DOTS_DEV_DIR/route)\" = phone ]"
wtype -k Return
until_ok 2000 state_is '.route == "device"'
check "Enter again switches it back to device" state_is '.route == "device"'

# A unit that failed draws its error in the danger tone on one line, cut with an ellipsis, however long the error.
long=$(printf 'mail: %.0s' {1..2}; printf 'x%.0s' {1..190})
jq -n --arg e "$long" '{mail: {ok: false, lastRun: 1, lastOk: null, error: $e}, notes: {ok: true, lastRun: 1, lastOk: 1}}' >"$XDG_STATE_HOME/dots/sync.json"
until_ok 3000 state_is '.rows | index("mail") != null'
check "Route lists each sync unit as a row ($(control_state | jq -c .rows))" state_is '.rows == ["Questions ring on", "mail", "notes"]'
check "the failed unit's row draws in the danger tone ($(control_state | jq -c .tones))" state_is '.tones[1] == "danger" and .tones[2] == ""'
check "its error is cut on one line with an ellipsis ($(control_state | jq -c '.detailsDrawn[1]'))" state_is '(.detailsDrawn[1] | endswith("…")) and .detailLines[1] == 1'
wtype -k Escape

exit $((fails > 0))
}
