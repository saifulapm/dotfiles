#!/usr/bin/env bash
# Mod+C grows the island into Control's Home: board 4's clock and tiles, 640 px wide, fill only; a connected network inverts the Wi-Fi tile and names it.
{
source "$(dirname "$0")/lib.sh"
source "$(dirname "$0")/pointer.bash"

island() { timeout 0.5 qs ipc call island state 2>/dev/null; }
island_is() { island | jq -e "$@" >/dev/null 2>&1; }
control() { timeout 0.5 qs ipc call control state 2>/dev/null; }
control_is() { control | jq -e "$@" >/dev/null 2>&1; }
px() { grim -g "$1,$2 1x1" -t ppm - 2>/dev/null | tail -c3 | od -An -tx1 | tr -d ' \n'; }
at_rest() { island_is '.surface == null and .animating == false'; }
surfaces_focus() { niri msg -j layers | jq -e --arg k "$1" 'any(.[]; .namespace == "dots-surfaces" and .keyboard_interactivity == $k)' >/dev/null; }
mod_c() { niri msg action spawn -- dots-call control toggle; }
open_control() {
  mod_c
  until_ok 3000 island_is '.surface == "control" and .animating == false'
  until_ok 2000 surfaces_focus Exclusive
  until_ok 2000 control_is '.keyboard and .settled'
}
tile() { control | jq -c --arg t "$1" '.tiles[] | select(.title == $t)'; }
tile_is() { control | jq -e --arg t "$1" ".tiles[] | select(.title == \$t) | $2" >/dev/null 2>&1; }

# Quickshell's NetworkManager client talks to the system bus, which in the nested session is the nested session bus.
bus() { busctl --address="$DBUS_SESSION_BUS_ADDRESS" "$@"; }
# Dots Secured takes jk-hl-pass, a password of the keys that move and step Control.
DOTS_FAKE_SECURED_PSK=jk-hl-pass DBUS_SYSTEM_BUS_ADDRESS=$DBUS_SESSION_BUS_ADDRESS "$repo/bin/dev-fake-networkmanager" &
fake_pid=$!
cleanup() {
  pointer_stop
  kill "$fake_pid" 2>/dev/null
}
fake_up() { bus status org.freedesktop.NetworkManager >/dev/null 2>&1; }
until_ok 5000 fake_up
# Quickshell looks for NetworkManager once, when the shell starts, so the shell restarts to find the double.
systemctl --user restart "$DOTS_DEV_UNIT"
surfaces_mapped() { niri msg -j layers | jq -e 'any(.[]; .namespace == "dots-surfaces")' >/dev/null; }
until_ok 10000 surfaces_mapped
until_ok 5000 shell_status >/dev/null
until_ok 5000 at_rest

read -r ow _ < <(niri msg -j outputs | jq -r '.[] | .logical | "\(.width) \(.height)"')
want=$((ow - 48 < 640 ? ow - 48 : 640))
open_control
check "Mod+C sets surface to control and the island $want px wide ($(island | jq -c '{surface, width}'))" island_is --argjson w "$want" '.surface == "control" and .width == $w'
titles='["Wi-Fi","Bluetooth","Sound","Brightness","Record screen","Battery","Sync","Do Not Disturb","Stay awake","Lock","Power"]'
check "control state lists the tiles in board order ($(control | jq -c '[.tiles[].title]'))" control_is --argjson t "$titles" '[.tiles[].title] == $t'
check "Home is the clock and the tiles with no legend row: the island is 340 px tall ($(island | jq .height))" island_is '.height == 340'
check "it opens on Home with Wi-Fi focused ($(control | jq -c '{page, cursor}'))" control_is '.page == "home" and .cursor == "wifi"'
check "the big clock is 34 px and reads the time ($(control | jq -c .clock))" control_is '.clock.px == 34 and (.clock.text | test("^[0-9]{2}:[0-9]{2}$"))'
check "Do Not Disturb is off and its switch with it ($(tile "Do Not Disturb"))" tile_is "Do Not Disturb" '.on == false'

# Fill only: a tile's first row of pixels is its fill, the same as three rows further in.
edge_free() {
  local t x y top inner
  t=$(tile "$1")
  x=$(jq -r '.box.x + .box.w / 2 | floor' <<<"$t")
  y=$(jq -r '.box.y | ceil' <<<"$t")
  top=$(px "$x" "$y")
  inner=$(px "$x" $((y + 3)))
  echo "     $1: top $top, inside $inner"
  [ -n "$top" ] && [ "$top" = "$inner" ]
}
for t in Bluetooth Battery "Do Not Disturb" Lock; do
  check "the $t tile has no edge: its first row is its fill" edge_free "$t"
done

# A known network joined from its page inverts the Wi-Fi tile, which then names it.
timeout 0.5 qs ipc call control section wifi
until_ok 2000 control_is '.page == "wifi"'
until_ok 5000 control_is '.rows | index("Dots Home") != null'
select_home() {
  local i
  i=$(control | jq '.rows | index("Dots Home")')
  for _ in 1 2 3 4; do
    control_is --argjson i "$i" '.selected == $i' && return 0
    if control_is --argjson i "$i" '.selected < $i'; then wtype j; else wtype k; fi
    sleep 0.15
  done
  return 1
}
until_ok 3000 select_home
wtype -k Return
until_ok 5000 control_is '.details[.rows | index("Dots Home")] == "connected"'
wtype -k Escape
until_ok 2000 control_is '.page == "home"'
until_ok 3000 tile_is "Wi-Fi" '.on'
check "with Dots Home connected the Wi-Fi tile is inverted and names it ($(tile Wi-Fi))" tile_is "Wi-Fi" '.on and .label == "Dots Home"'
check "and Esc came back to Home with Wi-Fi focused" control_is '.cursor == "wifi"'
# The focused tile dims a little, so the fill is read with the cursor moved off it.
wtype l
until_ok 2000 control_is '.cursor == "bluetooth"'
inverted() {
  local t x y fill
  t=$(tile Wi-Fi)
  x=$(jq -r '.box.x + .box.w - 20 | floor' <<<"$t")
  y=$(jq -r '.box.y + 4 | floor' <<<"$t")
  fill=$(px "$x" "$y")
  echo "     Wi-Fi tile fill $fill against the island text $(control | jq -r '.tiles[0].fill')"
  [ "#$fill" = "$(control | jq -r '.tiles[0].fill' | tr 'A-F' 'a-f')" ]
}
check "its fill is the island's text, drawn" inverted

wtype -k Escape
until_ok 3000 at_rest
check "Esc on Home closes Control" at_rest

# The password field takes every key: jk-hl-pass types whole and moves nothing; a click outside closes only the field, the next one Control.
last_psk() { bus call org.freedesktop.NetworkManager /org/freedesktop/NetworkManager org.dots.FakeNM LastPsk 2>/dev/null; }
select_row() {
  local i
  i=$(control | jq --arg t "$1" '.rows | index($t)')
  for _ in 1 2 3 4; do
    control_is --argjson i "$i" '.selected == $i' && return 0
    if control_is --argjson i "$i" '.selected < $i'; then wtype j; else wtype k; fi
    sleep 0.15
  done
  return 1
}
secured_field() {
  open_control
  wtype -k Return
  until_ok 2000 control_is '.page == "wifi"'
  until_ok 3000 select_row "Dots Secured"
  wtype -k Return
  until_ok 3000 control_is '.line'
}
secured_field
row=$(control | jq .selected)
wtype jk-hl-pass
until_ok 2000 control_is '.pskLength == 10'
check "jk-hl-pass typed in the field reads whole ($(control | jq -c '{pskLength, field: .field.text}'))" control_is '.pskLength == 10 and .field.text == "••••••••••"'
check "and moves no row or tile ($(control | jq -c '{page, selected, cursor}'))" control_is --argjson r "$row" '.page == "wifi" and .selected == $r and .cursor == "wifi"'
point click 100 1000
until_ok 2000 control_is '.line == false'
check "a click on the paper closes only the field ($(control | jq -c '{open, page, line}'))" control_is '.open and .page == "wifi" and .line == false and .pskLength == 0'
point click 100 1000
until_ok 3000 at_rest
check "the next click closes Control" control_is '.open == false'

secured_field
wtype jk-hl-pass
until_ok 2000 control_is '.pskLength == 10'
wtype -k Return
until_ok 5000 control_is '.details[.rows | index("Dots Secured")] == "connected"'
check "Enter joins Dots Secured, and its row reads connected ($(control | jq -c .detailsDrawn))" control_is '.details[.rows | index("Dots Secured")] == "connected"'
check "with the password it was typed as ($(last_psk))" test "$(last_psk)" = 's "jk-hl-pass"'
wtype -k Escape
wtype -k Escape
until_ok 3000 at_rest
exit "$fails"
}
