#!/usr/bin/env bash
# A surface's card, polkit's, is the paper in a square 1 px accent edge with no shadow; the island's own shape is island-rest.sh's.
{
source "$(dirname "$0")/lib.sh"
unset TMUX

# pkexec always reaches the live polkitd, so a fake authority on the nested bus asks the nested shell's agent, as in polkit.sh.
fake() { busctl --address="$DBUS_SESSION_BUS_ADDRESS" call org.freedesktop.PolicyKit1 /org/freedesktop/PolicyKit1/Authority org.dots.FakePolkit "$@"; }
polkit_state() { timeout 0.5 qs ipc call polkit state 2>/dev/null; }
polkit_is() { polkit_state | jq -e "$1" >/dev/null 2>&1; }
surfaces_focus() { niri msg -j layers | jq -e --arg k "$1" 'any(.[]; .namespace == "dots-surfaces" and .keyboard_interactivity == $k)' >/dev/null; }
polkit_open() { polkit_is ".open and .settled" && surfaces_focus Exclusive; }
polkit_closed() { polkit_is ".open == false and .drawing == false" && surfaces_focus None; }

read -r ox oy < <(niri msg -j outputs | jq -r 'first(.[]).logical | "\(.x) \(.y)"')

rgb() { grim -s 1 -t ppm -g "$1,$2 ${3:-1}x${4:-1}" - | mean_rgb; }
# Within tol per channel of r g b.
near() { local r g b t=${tol:-24}; read -r r g b < <(rgb "$1" "$2" "${6:-1}" "${7:-1}"); ((r - $3 <= t && $3 - r <= t && g - $4 <= t && $4 - g <= t && b - $5 <= t && $5 - b <= t)); }
ink() { near "$1" "$2" 21 23 27 "${3:-1}" "${4:-1}"; }
# Artboard's line #D0D7DE, close enough that the paper #E4E6EA is not it.
line() { tol=8 near "$1" "$2" 208 215 222 "${3:-1}" "${4:-1}"; }
# A panel's edge near its top left: Artboard's accent #3D5AFE, before it fades toward the paper.
edge() { tol=40 near "$1" "$2" 61 90 254 "${3:-1}" "${4:-1}"; }

until_ok 5000 shell_status >/dev/null

DBUS_SYSTEM_BUS_ADDRESS=$DBUS_SESSION_BUS_ADDRESS "$repo/bin/dev-fake-polkit" 9>&- &
fake_pid=$!
cleanup() { kill "$fake_pid" 2>/dev/null; }
until_ok 3000 fake Registered >/dev/null 2>&1
# The agent registers as the shell starts, so the shell restarts once the authority is up.
systemctl --user restart "$DOTS_DEV_UNIT"
until_ok 5000 polkit_is .registered
fake Begin s card >/dev/null
until_ok 3000 polkit_open
# The card's top-left corner and width as it reports them at rest, in screen pixels.
read -r cx cy cw < <(polkit_state | jq -r --argjson ox "$ox" --argjson oy "$oy" '.cardBox | "\(.x + $ox | floor) \(.y + $oy | floor) \(.w | floor)"')
# The accent edge runs down the left side to the corner itself, so the corner is square; inside it the card is the paper, and 2 px outside it the wash shows no shadow.
card() { edge "$cx" "$cy" && edge "$cx" $((cy + 40)) 1 10 && tol=6 near $((cx + 100)) $((cy + 3)) 228 230 234 && ! ink $((cx + cw + 2)) $((cy + 60)) && ! ink $((cx - 2)) $((cy + 40)); }
until_ok 2000 card
check "the card is the paper in a square 1 px accent edge, with no shadow past it ($cx $cy $cw)" card
wtype -k Escape
until_ok 2000 polkit_closed

exit $((fails > 0))
}
