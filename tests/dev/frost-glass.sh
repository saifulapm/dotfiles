#!/usr/bin/env bash
# Frost's panels are glass: Control asks niri to blur its own rounded box, so a white or a black window behind it reads the same inside it, and closing it drops the region; the other themes ask for none.
{
source "$(dirname "$0")/lib.sh"

control_state() { timeout 0.5 qs ipc call control state 2>/dev/null; }
state_is() { control_state | jq -e "$1" >/dev/null; }
blur_is() { timeout 0.5 qs ipc call shell blur 2>/dev/null | jq -e "$1" >/dev/null; }
status_theme() { shell_status | jq -e --arg t "$1" '.theme == $t and .transition == ""' >/dev/null; }
open_control() { niri msg action spawn -- dots-call control toggle; until_ok 3000 state_is '.open and .keyboard and .settled'; }
close_control() { wtype -k Escape; until_ok 2000 state_is '.open == false and .drawing == false'; }
in_theme() { "$repo/bin/dots" theme "$1" >/dev/null; until_ok 3000 status_theme "$1"; }
near() { local a b; read -r -a a <<<"$1"; read -r -a b <<<"$2"; for i in 0 1 2; do ((a[i] - b[i] <= $3 && b[i] - a[i] <= $3)) || return 1; done; }
mean_at() { grim -s 1 -t ppm -g "$1" - | mean_rgb; }

# A 40 x 40 box inside the card, 60 px in from its right edge and halfway down.
inside_geo() { control_state | jq -r '.cardBox | "\(.x + .w - 60 | round),\(.y + .h / 2 - 20 | round) 40x40"'; }
# A 200 x 3 strip inside the card's bottom edge, 2 px up from it, and one 2 px above its top edge: the open's lift moves the card, so a blur region left where the open began misses the one and blurs the other.
bottom_geo() { control_state | jq -r '.cardBox | "\(.x + .w / 2 - 100 | round),\(.y + .h - 5 | round) 200x3"'; }
above_geo() { control_state | jq -r '.cardBox | "\(.x + .w / 2 - 100 | round),\(.y - 5 | round) 200x3"'; }
# The same strip 40 px higher, where only the dim wash lies over the window.
wash_geo() { control_state | jq -r '.cardBox | "\(.x + .w / 2 - 100 | round),\(.y - 45 | round) 200x3"'; }
# The region asked for is the card's box with the theme's 10 px corner.
region_is_card='(.blurRegion | length) == 1 and (.blurRegion[0] as $r | .cardBox as $c | ([$r.x - $c.x, $r.y - $c.y, $r.w - $c.w, $r.h - $c.h] | map(fabs < 1) | all) and $r.radius == 10)'

foot_count() { niri msg -j windows | jq '[.[] | select(.app_id == "foot")] | length'; }
no_foot() { (($(foot_count) == 0)); }
# A maximised foot of one flat colour behind Control.
behind() {
  niri msg action spawn -- foot -c /dev/null -o "colors.background=$1"
  until_ok 5000 bash -c 'niri msg -j focused-window | jq -e ".app_id == \"foot\"" >/dev/null'
  niri msg action maximize-column
}

# The other panels, each opened the way its own check opens it. Polkit asks a fake authority on the nested bus, Pinentry a gpg key with a passphrase, the file picker its socket.
panels="notifs goals cheatsheet record themes tailscale accounts dns pass polkit pinentry picker"
fake() { busctl --address="$DBUS_SESSION_BUS_ADDRESS" call org.freedesktop.PolicyKit1 /org/freedesktop/PolicyKit1/Authority org.dots.FakePolkit "$@"; }
sock=$XDG_RUNTIME_DIR/dots-picker-$WAYLAND_DISPLAY.sock
passphrase=dots-test-phrase
fake_pid=0 asks=0
cleanup() { kill "$fake_pid" 2>/dev/null; gpgconf --kill gpg-agent 2>/dev/null; }

unset PINENTRY_USER_DATA GPG_TTY
mkdir -p -m 700 "$GNUPGHOME" "$DOTS_DEV_DIR/Downloads"
echo "pinentry-program $repo/bin/dots-pinentry" >"$GNUPGHOME/gpg-agent.conf"
gpg --batch --pinentry-mode loopback --passphrase "$passphrase" --quick-gen-key 'Dots Test <dots@test>' default default never 2>/dev/null
pass init dots@test >/dev/null
printf '%s\n' hunter2 | pass insert -e web/github.com >/dev/null
DBUS_SYSTEM_BUS_ADDRESS=$DBUS_SESSION_BUS_ADDRESS "$repo/bin/dev-fake-polkit" &
fake_pid=$!
until_ok 3000 fake Registered >/dev/null 2>&1
# The agent registers as the shell starts, so the shell restarts once the authority is up.
systemctl --user restart "$DOTS_DEV_UNIT"
until_ok 5000 shell_status >/dev/null

panel_state() { timeout 0.5 qs ipc call "$1" state 2>/dev/null; }
panel_is() { local p=$1; shift; panel_state "$p" | jq -e "$@" >/dev/null 2>&1; }
exclusive() { niri msg -j layers | jq -e 'any(.[]; .namespace == "dots-surfaces" and .keyboard_interactivity == "Exclusive")' >/dev/null; }
open_panel() {
  asks=$((asks + 1))
  case $1 in
    polkit) fake Begin s "g$asks" >/dev/null ;;
    pinentry)
      gpgconf --kill gpg-agent
      pass show web/github.com >/dev/null 2>&1 &
      ;;
    picker)
      node -e 'const s = require("net").connect(process.argv[1], () => s.write(process.argv[2] + "\n")); s.on("data", () => {}); s.on("close", () => process.exit())' "$sock" "$(jq -cn --arg f "$DOTS_DEV_DIR/Downloads" '{mode: "open", multiple: false, title: "Open File", app: "chromium-browser", folder: $f, name: "", filters: [], filter: 0, accept: ""}')" &
      ;;
    *) niri msg action spawn -- dots-call "$1" toggle ;;
  esac
  until_ok 8000 panel_is "$1" '(.open // .picking) and .settled' && until_ok 3000 exclusive
}
close_panel() { wtype -k Escape; until_ok 3000 panel_is "$1" '((.open // .picking) | not) and .drawing == false'; }

until_ok 5000 shell_status >/dev/null
in_theme frost

open_control
check "frost: Control's card is glass #d93b4252 ($(control_state | jq -c .cardFill))" state_is '.cardFill == "#d93b4252"'
check "frost: Control asks for one blur region, its card's box with radius 10 ($(control_state | jq -c '[.blurRegion, .cardBox]'))" state_is "$region_is_card"
check "frost: the Surfaces window asks niri for one region while Control draws" blur_is '.surfaces == 1'
in_geo=$(inside_geo)
bottom=$(bottom_geo)
above=$(above_geo)
wash=$(wash_geo)
close_control
check "frost: after Esc the Surfaces window asks for no region" blur_is '.surfaces == 0'

for p in $panels; do
  open_panel "$p"
  check "frost: $p asks for one blur region, its card's box with radius 10 ($(panel_state "$p" | jq -c '[.blurRegion, .cardBox]'))" panel_is "$p" "$region_is_card"
  check "frost: the Surfaces window asks niri for one region while $p draws" blur_is '.surfaces == 1'
  close_panel "$p"
  check "frost: after $p closes the Surfaces window asks for no region" blur_is '.surfaces == 0'
done

behind ffffff
# With Control closed the white foot shows where the card was, so no blurred box is left on the desktop.
white_up() { near "$(mean_at "$in_geo")" "255 255 255" 4; }
until_ok 5000 white_up
check "frost: a maximised white foot fills $in_geo with Control closed ($(mean_at "$in_geo"))" white_up
open_control
in_white=$(mean_at "$in_geo")
bottom_white=$(mean_at "$bottom")
above_white=$(mean_at "$above")
wash_white=$(mean_at "$wash")
close_control
until_ok 2000 white_up
check "frost: after Esc the white foot shows at $in_geo again ($(mean_at "$in_geo"))" white_up
niri msg action close-window
until_ok 3000 no_foot

behind 000000
black_up() { near "$(mean_at "$in_geo")" "0 0 0" 4; }
until_ok 5000 black_up
check "frost: a maximised black foot fills $in_geo with Control closed ($(mean_at "$in_geo"))" black_up
open_control
in_black=$(mean_at "$in_geo")
bottom_black=$(mean_at "$bottom")
close_control
niri msg action close-window
until_ok 3000 no_foot

check "frost: inside Control at $in_geo reads the same over a white foot ($in_white) and a black one ($in_black), within 3" near "$in_white" "$in_black" 3
check "frost: along Control's bottom edge at $bottom the glass reads the same over white ($bottom_white) and black ($bottom_black), within 3, so the region reaches the resting card" near "$bottom_white" "$bottom_black" 3
check "frost: just above Control at $above the white foot shows under the wash ($above_white), as 40 px higher ($wash_white), so no region is left above the resting card" near "$above_white" "$wash_white" 4

for t in paper artboard blueprint hi-fi; do
  in_theme "$t"
  open_control
  check "$t: Control asks for no blur region ($(control_state | jq -c .blurRegion))" state_is '.blurRegion == []'
  check "$t: the Surfaces window asks niri for no region" blur_is '.surfaces == 0'
  close_control
  for p in $panels; do
    open_panel "$p"
    check "$t: $p asks for no blur region ($(panel_state "$p" | jq -c .blurRegion))" panel_is "$p" '.blurRegion == []'
    check "$t: the Surfaces window asks niri for no region while $p draws" blur_is '.surfaces == 0'
    close_panel "$p"
  done
done

errors=$(qml_errors)
[ -n "$errors" ] && echo "$errors"
check "the shell's journal has no QML error" test -z "$errors"

exit $((fails > 0))
}
