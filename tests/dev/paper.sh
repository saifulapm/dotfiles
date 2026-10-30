#!/usr/bin/env bash
# just dev: its own bus, the Paper paper, and a shell systemd brings back within 1 s of a kill.
{
source "$(dirname "$0")/lib.sh"

check "WAYLAND_DISPLAY is printed" test -n "$WAYLAND_DISPLAY"
check "NIRI_SOCKET is printed" test -n "$NIRI_SOCKET"
check "the session bus is its own" test -n "$DBUS_SESSION_BUS_ADDRESS" -a "$DBUS_SESSION_BUS_ADDRESS" != "$live_bus"

until_ok 5000 shell_status >/dev/null
status=$(shell_status)
pid=$(systemctl --user show -p MainPID --value "$DOTS_DEV_UNIT")
real_rss=$(awk '/^VmRSS/ { print $2 }' "/proc/$pid/status")
echo "     status: $status (VmRSS $real_rss)"
check "the shell process has the nested bus" grep -qzxF "DBUS_SESSION_BUS_ADDRESS=$DBUS_SESSION_BUS_ADDRESS" "/proc/$pid/environ"
status_is_m1() { jq -e '.theme == "paper" and (.outputs | length) == 1 and .timers == 1' <<<"$status" >/dev/null; }
check "status names theme paper, one output, only the clock tick" status_is_m1
# The shell is still growing here, so an RSS read one call late is far off.
rss_now() { local said; said=$(jq .rssKiB <<<"$status"); ((said - real_rss < 2048 && real_rss - said < 2048)); }
check "status rssKiB is the RSS of that call" rss_now

paper_layer() { niri msg -j layers | jq -e 'any(.[]; .namespace == "dots-paper" and .layer == "Background")' >/dev/null; }
until_ok 3000 paper_layer
check "dots-paper is on the Background layer" paper_layer

# Mid-height near the left edge, clear of the margins and of the day's passage at the centre.
geo=$(niri msg -j outputs | jq -r 'first(.[]).logical | "\(.x + 20),\(.y + (.height / 2 | floor) - 5) 10x10"')
read -r r g b < <(grim -s 1 -t ppm -g "$geo" - | mean_rgb)
echo "     paper $geo: $r $g $b"
near() { (($1 - $2 <= 6 && $2 - $1 <= 6)); }
centre_is_paper() { near "${r:-0}" 241 && near "${g:-0}" 233 && near "${b:-0}" 216; }
check "the output's paper is #F1E9D8" centre_is_paper

# A colour the theme check refuses leaves the last good paper on screen, never black.
tokens=$XDG_STATE_HOME/dots/theme-out/shell.json
good=$(<"$tokens")
jq '.color.paper = "notacolor"' <<<"$good" >"$tokens"
sleep 1
read -r r g b < <(grim -s 1 -t ppm -g "$geo" - | mean_rgb)
printf '%s\n' "$good" >"$tokens"
check "a bad colour in shell.json keeps the paper ($r $g $b)" eval 'near "$r" 241 && near "$g" 233 && near "$b" 216'

# qs ipc calls made while a shell starts slow it by up to 1.5 s, so qs is asked only once the paper is back.
new_pid() { local p; p=$(systemctl --user show -p MainPID --value "$DOTS_DEV_UNIT"); [ "$p" != 0 ] && [ "$p" != "$pid" ]; }
pid=$(systemctl --user show -p MainPID --value "$DOTS_DEV_UNIT")
start=$(now_ms)
kill -9 "$pid"
until_ok 3000 new_pid && until_ok 3000 paper_layer && until_ok 3000 shell_status >/dev/null
elapsed=$(($(now_ms) - start))
# The paper is back at about 750 ms; the build after its first frame answers by about 1000 since m24, so 1100 (#9CZXS2QM).
check "status answers again ${elapsed} ms after kill -9" test "$elapsed" -le 1100

dev_stop
check "the transient unit is gone" test "$(systemctl --user show -p LoadState --value "$DOTS_DEV_UNIT")" = not-found
check "the temp dir is deleted" test ! -e "$DOTS_DEV_DIR"

exit $((fails > 0))
}
