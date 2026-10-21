#!/usr/bin/env bash
# dots-capture reads text and a QR code off the nested screen to the clipboard, a QR code never reaches the clip history, and each result shows as the island's capture pill, a colour with its swatch.
{
source "$(dirname "$0")/lib.sh"

island() { timeout 0.5 qs ipc call island state 2>/dev/null; }
pill_is() { island | jq -e --arg t "$1" --arg s "${2:-}" '.mode == "capture" and .text == $t and .swatch == (if $s == "" then null else $s end)' >/dev/null 2>&1; }
rests() { island | jq -e '.mode == "rest"' >/dev/null 2>&1; }
clip() { cliphist -db-path "$XDG_STATE_HOME/dots/clips.db" "$@"; }
listed() { clip list 2>/dev/null | cut -f2- | grep -qxF "$1"; }
focused() { niri msg -j windows | jq -e --arg a "$1" 'any(.[]; .is_focused and .app_id == $a)' >/dev/null; }
# niri reports no place for a tiled window, so the focused one floats at 200,200 and its contents start there plus the border.
origin() { niri msg -j windows | jq -r 'first(.[] | select(.is_focused)).layout | select(.tile_pos_in_workspace_view == [200, 200]) | "\(200 + .window_offset_in_tile[0] | floor) \(200 + .window_offset_in_tile[1] | floor) \(.window_size[0]) \(.window_size[1])"'; }
float() {
  niri msg action toggle-window-floating
  niri msg action move-floating-window -x 200 -y 200
  until_ok 3000 test -n "$(origin)"
  # The move animates, so the grab waits for it to land.
  sleep 0.5
  read -r x y w h <<<"$(origin)"
}
capture() { "$repo/bin/dots-capture" "$@"; }

until_ok 5000 shell_status >/dev/null
qr=$(mktemp --suffix=.png)
cleanup() { rm -f "$qr"; }

# Black on white at 36 pt with the cursor hidden, as a page of text reads; the live foot.ini's colours win over [colors], so both themes are set.
niri msg action spawn -- foot -c /dev/null -f monospace:size=36 -o colors-dark.background=ffffff -o colors-light.background=ffffff -o colors-dark.foreground=000000 -o colors-light.foreground=000000 \
  -e sh -c "printf '\033[?25lShip v2 today'; sleep 600"
until_ok 5000 focused foot
float

wl-copy 'clip before'
until_ok 3000 listed 'clip before'
capture ocr --region "$x,$y 600x120"
check "ocr copies the line it reads (got '$(wl-paste)')" test "$(wl-paste)" = 'Ship v2 today'
check "the pill reads Text copied · 13 characters" until_ok 1000 pill_is 'Text copied · 13 characters'
until_ok 3000 rests

capture ocr --region "$x,$((y + h / 2)) 600x120"
check "ocr over an empty region says No text found" until_ok 1000 pill_is 'No text found'
check "and leaves the clipboard unchanged" test "$(wl-paste)" = 'Ship v2 today'
until_ok 3000 rests

niri msg action close-window
qrencode -s 8 -o "$qr" 'https://example.com/x'
niri msg action spawn -- imv "$qr"
until_ok 5000 focused imv
sleep 0.5
# The code is the only one on screen, so the region is the whole output.
capture qr --region "$(niri msg -j outputs | jq -r 'first(.[]).logical | "\(.x),\(.y) \(.width)x\(.height)"')"
check "qr copies the code's URL (got '$(wl-paste)')" test "$(wl-paste)" = 'https://example.com/x'
check "the pill reads QR code copied" until_ok 1000 pill_is 'QR code copied'
sleep 0.5
check "the clip history does not hold the URL" bash -c "! cliphist -db-path '$XDG_STATE_HOME/dots/clips.db' list | grep -qF example.com"
check "the clip history still holds the copy before it" listed 'Ship v2 today'
until_ok 3000 rests

capture qr --region "0,0 40x40"
check "qr with no code in the region says No QR code found" until_ok 1000 pill_is 'No QR code found'
until_ok 3000 rests

"$repo/bin/dots-call" island capture 'Copied #C8381E' ''
until_ok 1000 pill_is 'Copied #C8381E'
plain=$(island | jq .width)
"$repo/bin/dots-call" island capture 'Copied #C8381E' '#c8381e'
check "a colour's pill draws its swatch" until_ok 1000 pill_is 'Copied #C8381E' '#C8381E'
check "and grows by the swatch and its gap (20 px)" test "$(island | jq --argjson p "$plain" '.width - $p')" = 20
until_ok 3000 rests

qs ipc call island capture $'Ship\nv2\u202e today\e[31m' 'red' >/dev/null
check "a forged capture is one plain line with no swatch" until_ok 1000 pill_is 'Ship v2 today [31m'

exit $((fails > 0))
}
