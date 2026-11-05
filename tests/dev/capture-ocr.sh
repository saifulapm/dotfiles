#!/usr/bin/env bash
# dots-capture reads text and a QR code off the nested screen to the clipboard, a QR code never reaches the clip history, and each result shows in the notification card, a colour with its swatch.
{
source "$(dirname "$0")/lib.sh"

island() { timeout 0.5 qs ipc call island state 2>/dev/null; }
state_is() { island | jq -e "$1" >/dev/null 2>&1; }
# shows <text> <test on .capture>: the capture is what the island shows, and what it drew passes the test.
shows() { island | jq -e --arg t "$1" ".mode == \"capture\" and .text == \$t and (.capture | $2)" >/dev/null 2>&1; }
# How many notifications the Mod+A history holds; a capture never adds one.
kept() { timeout 0.5 qs ipc call notifs state 2>/dev/null | jq .count; }
rests() { island | jq -e '.mode == "rest"' >/dev/null 2>&1; }
clip() { cliphist -db-path "$XDG_STATE_HOME/dots/clips.db" "$@"; }
listed() { clip list 2>/dev/null | cut -f2- | grep -qxF "$1"; }
focused() { niri msg -j windows | jq -e --arg a "$1" 'any(.[]; .is_focused and .app_id == $a)' >/dev/null; }
# niri reports no place for a tiled window, so the focused one floats at 200,200 and its contents start there plus the border.
origin() { niri msg -j windows | jq -r 'first(.[] | select(.is_focused)).layout | select(.tile_pos_in_workspace_view == [200, 200]) | "\(200 + .window_offset_in_tile[0] | floor) \(200 + .window_offset_in_tile[1] | floor) \(.window_size[0]) \(.window_size[1])"'; }
placed() { test -n "$(origin)"; }
float() {
  niri msg action toggle-window-floating
  niri msg action move-floating-window -x 200 -y 200
  until_ok 3000 placed
  # The move animates, so the grab waits for it to land.
  sleep 0.5
  read -r x y w h <<<"$(origin)"
}
capture() { "$repo/bin/dots-capture" "$@"; }

until_ok 5000 shell_status >/dev/null
qr=$(mktemp --suffix=.png)
# imv outlives the nested niri that spawned it and then spins a core, so it goes before the session does.
cleanup() { pkill -f -- "imv-wayland $qr"; rm -f "$qr"; }

# Black on white at 36 pt with the cursor hidden, as a page of text reads; the live foot.ini's colours win over [colors], so both themes are set.
niri msg action spawn -- foot -c /dev/null -f monospace:size=36 -o colors-dark.background=ffffff -o colors-light.background=ffffff -o colors-dark.foreground=000000 -o colors-light.foreground=000000 \
  -e sh -c "printf '\033[?25lShip v2 today'; sleep 600"
until_ok 5000 focused foot
float

wl-copy 'clip before'
until_ok 3000 listed 'clip before'
capture ocr --region "$x,$y 600x120"
check "ocr copies the line it reads (got '$(wl-paste)')" test "$(wl-paste)" = 'Ship v2 today'
check "the card reads Capture over Text copied · 13 characters and how it was read" until_ok 1000 shows 'Text copied · 13 characters' '.drawn == "card" and .head == "Capture" and .title == "Text copied · 13 characters" and .detail == "eng + ben · from region" and .swatch == null'
echo "     capture: $(island | jq -c .capture)"
until_ok 3000 rests

capture ocr --region "$x,$((y + h / 2)) 600x120"
check "ocr over an empty region draws No text found" until_ok 1000 shows 'No text found' '.drawn == "card" and .title == "No text found"'
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
check "the card reads QR code copied and nothing of the code" until_ok 1000 shows 'QR code copied' '.drawn == "card" and .title == "QR code copied" and .detail == "from region"'
sleep 0.5
check "the clip history does not hold the URL" bash -c "! cliphist -db-path '$XDG_STATE_HOME/dots/clips.db' list | grep -qF example.com"
check "the clip history still holds the copy before it" listed 'Ship v2 today'
until_ok 3000 rests

# qrencode writes UTF-8 with no ECI, which zbar would read as Shift-JIS.
niri msg action close-window
qrencode -s 8 -o "$qr" 'নমস্কার café'
niri msg action spawn -- imv "$qr"
until_ok 5000 focused imv
sleep 0.5
capture qr --region "$(niri msg -j outputs | jq -r 'first(.[]).logical | "\(.x),\(.y) \(.width)x\(.height)"')"
check "qr copies Bangla and an accent byte for byte (got '$(wl-paste)')" test "$(wl-paste)" = 'নমস্কার café'
until_ok 3000 rests

capture qr --region "0,0 40x40"
check "qr with no code in the region says No QR code found" until_ok 1000 shows 'No QR code found' '.title == "No QR code found"'
until_ok 3000 rests

kept=$(kept)
"$repo/bin/dots-call" island capture colour Copied '#c8381e'
check "a colour's card reads Capture over Copied #c8381e, its tile the swatch" until_ok 1000 shows 'Copied #c8381e' '.drawn == "card" and .head == "Capture" and .title == "Copied #c8381e" and .detail == "colour picked" and .swatch == "#C8381E"'
check "the card is no notification" state_is '.mode == "capture" and .note == null'
until_ok 3000 rests

qs ipc call island capture ocr $'Ship\nv2\u202e today\e[31m' $'2\n\u202echaracters' >/dev/null
check "a forged capture draws one plain line, and no swatch" until_ok 1000 shows 'Ship v2 today [31m · 2 characters' '.title == "Ship v2 today [31m · 2 characters" and .swatch == null'
until_ok 3000 rests
long=$(printf 'x%.0s' {1..200})
qs ipc call island capture ocr "$long" '' >/dev/null
check "a 200-character title elides inside the island" until_ok 1000 shows "$long" '.drawn == "card" and .titleElided'
check "and the island is no wider than 560 px ($(island | jq .width))" state_is '.width | type == "number" and . > 300 and . <= 560'
until_ok 3000 rests
qs ipc call island capture annotate Copied '' >/dev/null
sleep 0.3
check "a capture of an unknown kind shows nothing" rests
qs ipc call island capture ocr '' '' >/dev/null
sleep 0.3
check "a capture with no words shows nothing" rests

qs ipc call island capture ocr $'Ship\nv2\u202e' $'2\n\u202echaracters' >/dev/null
check "a forged capture's card is one plain line" until_ok 1000 shows 'Ship v2 · 2 characters' '.title == "Ship v2 · 2 characters"'
until_ok 3000 rests
check "no capture reached the notification history ($kept before, $(kept) after)" eval '[[ $kept =~ ^[0-9]+$ ]] && test "$(kept)" = "$kept"'

exit $((fails > 0))
}
