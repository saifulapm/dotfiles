#!/usr/bin/env bash
# With Artboard, every system surface is a selected frame: an accent label names it above its top-left handle.
{
source "$(dirname "$0")/lib.sh"
unset TMUX

# pkexec always reaches the live polkitd, so a fake authority on the nested bus asks the nested shell's agent instead.
fake() { busctl --address="$DBUS_SESSION_BUS_ADDRESS" call org.freedesktop.PolicyKit1 /org/freedesktop/PolicyKit1/Authority org.dots.FakePolkit "$@"; }
DBUS_SYSTEM_BUS_ADDRESS=$DBUS_SESSION_BUS_ADDRESS "$repo/bin/dev-fake-polkit" &
fake_pid=$!
cleanup() { kill "$fake_pid" 2>/dev/null; }
until_ok 3000 fake Registered >/dev/null 2>&1
# The agent registers as the shell starts, so the shell restarts once the authority is up.
systemctl --user restart "$DOTS_DEV_UNIT"
until_ok 5000 shell_status >/dev/null

status_theme() { shell_status | jq -e --arg t "$1" '.theme == $t' >/dev/null; }
is_open() { timeout 0.5 qs ipc call "$1" state 2>/dev/null | jq -e "$2" >/dev/null; }

read -r ox oy ow < <(niri msg -j outputs | jq -r 'first(.[]).logical | "\(.x) \(.y) \(.width)"')

# Accent (#3D5AFE) pixels in a strip, within 40 per channel.
accent_px() {
  grim -s 1 -t ppm -g "$1" - | node -e '
    const b = require("fs").readFileSync(0);
    const head = b.toString("latin1").match(/^P6\s+(\d+)\s+(\d+)\s+(\d+)\s/), px = b.subarray(head[0].length);
    const hit = [];
    for (let i = 0; i < head[1] * head[2]; i++) if (Math.abs(px[i * 3] - 61) <= 40 && Math.abs(px[i * 3 + 1] - 90) <= 40 && Math.abs(px[i * 3 + 2] - 254) <= 40) hit.push(i);
    console.log(hit.length, hit.length ? hit[0] : -1);
  '
}
# The label as drawn, read from the surface's own state: the Text item's text and visibility, not the label it was given.
drawn_label() { is_open "$1" ".frameLabel.visible and .frameLabel.text == \"$2\""; }
# The card's top-left handle is the first accent pixel down a column 3 px left of the card; the label sits 16 px above it.
labelled() {
  local x=$((ox + $1)) n top
  read -r n top < <(accent_px "$((x - 3)),$oy 1x1200")
  ((top > 16)) || return 1
  read -r n _ < <(accent_px "$((x + 1)),$((oy + top - 16)) 80x13")
  ((n > 15))
}

"$repo/bin/dots" theme artboard >/dev/null
until_ok 2000 status_theme artboard

niri msg action spawn -- dots-call launcher toggle
until_ok 3000 is_open launcher .open
until_ok 2000 labelled $(((ow - 640) / 2))
check "the launcher card carries its frame label" labelled $(((ow - 640) / 2))
check "the launcher's drawn frame label reads Launcher" drawn_label launcher Launcher
timeout 0.5 qs ipc call launcher close

niri msg action spawn -- dots-call control toggle
until_ok 3000 is_open control '.open and .settled'
until_ok 2000 labelled $(((ow - 720) / 2))
check "Control carries its frame label" labelled $(((ow - 720) / 2))
check "Control's drawn frame label reads Control" drawn_label control Control
timeout 0.5 qs ipc call control close

niri msg action spawn -- dots-call notifs toggle
until_ok 3000 is_open notifs '.open and .settled'
until_ok 2000 labelled $(((ow - 640) / 2))
check "the notification centre carries its frame label" labelled $(((ow - 640) / 2))
check "the notification centre's drawn frame label reads Notifications" drawn_label notifs Notifications
timeout 0.5 qs ipc call notifs close

fake Begin s c1 >/dev/null
until_ok 3000 is_open polkit '.open and .settled'
until_ok 2000 labelled $(((ow - 520) / 2))
check "the polkit prompt carries its frame label" labelled $(((ow - 520) / 2))
check "the polkit prompt's drawn frame label reads Authenticate" drawn_label polkit Authenticate
wtype -k Escape
until_ok 2000 is_open polkit '(.open | not) and .drawing == false'

niri msg action spawn -- dots-call record toggle
until_ok 3000 is_open record '.picking and .settled'
hint_x=$(timeout 0.5 qs ipc call record state | jq .region.x)
until_ok 2000 labelled "$hint_x"
check "the recorder's hint carries its frame label" labelled "$hint_x"
check "the recorder's drawn frame label reads Record" drawn_label record Record
wtype -k Escape
until_ok 2000 is_open record '(.picking | not) and .drawing == false'

# Each theme's key style is a different width, so the apps footer must fit the card in all three.
for t in paper artboard blueprint; do
  "$repo/bin/dots" theme "$t" >/dev/null
  until_ok 2000 status_theme "$t"
  niri msg action spawn -- dots-call launcher toggle
  until_ok 3000 is_open launcher .open
  until_ok 2000 is_open launcher '.legendOverflow == false'
  check "$t: the launcher's prefix legend fits its card" is_open launcher '.legendOverflow == false'
  timeout 0.5 qs ipc call launcher close
  until_ok 2000 is_open launcher '.open | not'
done

"$repo/bin/dots" theme paper >/dev/null
exit $((fails > 0))
}
