#!/usr/bin/env bash
# dots theme recolours the paper, niri, an open foot, tmux and GTK in this session, and keeps every window.
{
source "$(dirname "$0")/lib.sh"
unset TMUX

until_ok 5000 shell_status >/dev/null
near() { (($1 - $2 <= 6 && $2 - $1 <= 6)); }
windows() { niri msg -j windows | jq -c '[.[] | .id] | sort'; }
gtk_scheme() { gsettings get org.gnome.desktop.interface color-scheme; }
gtk_font() { gsettings get org.gnome.desktop.interface font-name; }

niri msg action spawn -- foot
foot_up() { niri msg -j windows | jq -e 'any(.[]; .app_id == "foot")' >/dev/null; }
until_ok 5000 foot_up
niri msg action spawn -- foot
two_windows() { test "$(niri msg -j windows | jq length)" = 2; }
until_ok 5000 two_windows
focused() { niri msg -j focused-window | jq -r .id; }
tmux new-session -d -s dots-themes 'sleep 300'
before=$(windows)
focus_before=$(focused)
# Low in foot's window, below the prompt, is only its background.
inside="200,600 10x10"
foot_is() { local r g b; read -r r g b < <(grim -s 1 -t ppm -g "$inside" - | mean_rgb); near "$r" "$1" && near "$g" "$2" && near "$b" "$3"; }
# The nested foot starts on the live foot.ini, so Paper's palette arrives the same way as every other.
"$repo/bin/dots" theme paper
until_ok 1000 foot_is 250 246 236
check "foot shows Paper's surface #FAF6EC" foot_is 250 246 236

start=$(now_ms)
"$repo/bin/dots" theme blueprint
status=$?
check "dots theme blueprint exits 0" test "$status" = 0
until_ok 1000 foot_is 10 21 38
elapsed=$(($(now_ms) - start))
check "the open foot shows Blueprint's #0A1526 ${elapsed} ms after the call" test "$elapsed" -le 300
check "the state file reads blueprint" test "$(<"$XDG_STATE_HOME/dots/theme")" = blueprint
status_theme() { shell_status | jq -e --arg t "$1" '.theme == $t' >/dev/null; }
until_ok 1000 status_theme blueprint
check "shell status reports blueprint" status_theme blueprint
check "tmux status-style carries #7fa6b8 ($(tmux show -g status-style))" bash -c 'tmux show -g status-style | grep -q "#7fa6b8"'
check "GTK prefers dark ($(gtk_scheme))" test "$(gtk_scheme)" = "'prefer-dark'"
check "GTK draws with the theme's UI font ($(gtk_font))" test "$(gtk_font)" = "'Maple Mono 11'"
json_has() { jq -e "$2" "$1" >/dev/null; }
check "Chromium's policy colour is Blueprint's surface" json_has "$DOTS_CHROMIUM_POLICY_DIR/color.json" '(.BrowserThemeColor | ascii_downcase) == "#0a1526"'
switch_ms=$(jq -r .ms "$XDG_STATE_HOME/dots/theme-switch.json")
check "theme-switch.json records paper to blueprint in ${switch_ms} ms" json_has "$XDG_STATE_HOME/dots/theme-switch.json" '.from == "paper" and .to == "blueprint" and .ms <= 300'
kdl=$XDG_STATE_HOME/dots/theme-out/niri.kdl
check "niri's fragment has the cyan border" grep -q 'active-color "#7FE3F0"' "$kdl"
check "every window survives with its id ($before)" test "$(windows)" = "$before"

# A start stamp that is not a time in ms is ignored, never evaluated.
DOTS_SWITCH_T0='1; touch '"$DOTS_DEV_DIR"'/pwned' "$repo/bin/dots" theme artboard
check "a bad DOTS_SWITCH_T0 still switches" json_has "$XDG_STATE_HOME/dots/theme-switch.json" '.to == "artboard" and .ms >= 0 and .ms <= 300'
check "and runs nothing" test ! -e "$DOTS_DEV_DIR/pwned"
DOTS_SWITCH_T0=1000000000000 "$repo/bin/dots" theme blueprint
check "a stamp from 2001 is not taken" json_has "$XDG_STATE_HOME/dots/theme-switch.json" '.to == "blueprint" and .ms >= 0 and .ms <= 300'
DOTS_SWITCH_T0=9999999999999 "$repo/bin/dots" theme artboard
check "nor one from 2286" json_has "$XDG_STATE_HOME/dots/theme-switch.json" '.to == "artboard" and .ms >= 0 and .ms <= 300'
check "after artboard the fragment's corner radius is 14" grep -q 'geometry-corner-radius 14' "$kdl"
"$repo/bin/dots" theme paper
check "after paper the shadow is hard at 3,3" grep -Pzq 'softness 0\s+spread 0\s+offset x=3 y=3' "$kdl"
check "GTK prefers light with paper ($(gtk_scheme))" test "$(gtk_scheme)" = "'prefer-light'"
until_ok 1000 foot_is 250 246 236
check "foot is back on Paper's surface" foot_is 250 246 236
check "every window still has its id" test "$(windows)" = "$before"
check "the same window keeps focus ($focus_before)" test "$(focused)" = "$focus_before"

exit $((fails > 0))
}
