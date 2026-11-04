#!/usr/bin/env bash
# dots colorscheme recolours the paper, niri, an open foot, tmux and GTK in this session, and keeps every window.
{
export DOTS_DEV_SCHEME=artboard
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
# The nested foot starts on the live foot.ini, so Artboard's palette arrives the same way as every other.
"$repo/bin/dots" colorscheme artboard
until_ok 1000 foot_is 255 255 255
check "foot shows Artboard's surface #FFFFFF" foot_is 255 255 255

start=$(now_ms)
"$repo/bin/dots" colorscheme catppuccin-mocha
status=$?
check "dots colorscheme catppuccin-mocha exits 0" test "$status" = 0
until_ok 1000 foot_is 30 30 46
elapsed=$(($(now_ms) - start))
check "the open foot shows Catppuccin Mocha's #1E1E2E ${elapsed} ms after the call" test "$elapsed" -le 300
check "the state file reads catppuccin-mocha" test "$(<"$XDG_STATE_HOME/dots/theme")" = catppuccin-mocha
status_theme() { shell_status | jq -e --arg t "$1" '.theme == $t' >/dev/null; }
until_ok 1000 status_theme catppuccin-mocha
check "shell status reports catppuccin-mocha" status_theme catppuccin-mocha
check "tmux status-style carries #a6adc8 ($(tmux show -g status-style))" bash -c 'tmux show -g status-style | grep -q "#a6adc8"'
check "GTK prefers dark ($(gtk_scheme))" test "$(gtk_scheme)" = "'prefer-dark'"
check "GTK draws with the colorscheme's UI font ($(gtk_font))" test "$(gtk_font)" = "'Maple Mono 11'"
json_has() { jq -e "$2" "$1" >/dev/null; }
check "Chromium's theme extension frames in Catppuccin Mocha's paper" json_has "$XDG_STATE_HOME/dots/theme-out/chromium-theme/manifest.json" '.theme.colors.frame == [17, 17, 27]'
check "the switch names no app that missed it ($(cat "$XDG_STATE_HOME/dots/theme-out/notice"))" test ! -s "$XDG_STATE_HOME/dots/theme-out/notice"
switch_ms=$(jq -r .ms "$XDG_STATE_HOME/dots/theme-switch.json")
check "theme-switch.json records artboard to catppuccin-mocha in ${switch_ms} ms" json_has "$XDG_STATE_HOME/dots/theme-switch.json" '.from == "artboard" and .to == "catppuccin-mocha" and .ms <= 300'
kdl=$XDG_STATE_HOME/dots/theme-out/niri.kdl
check "niri's fragment has Catppuccin Mocha's ink border" grep -q 'active-color "#CDD6F4"' "$kdl"
check "every window survives with its id ($before)" test "$(windows)" = "$before"

# A start stamp that is not a time in ms is ignored, never evaluated.
DOTS_SWITCH_T0='1; touch '"$DOTS_DEV_DIR"'/pwned' "$repo/bin/dots" colorscheme artboard
check "a bad DOTS_SWITCH_T0 still switches" json_has "$XDG_STATE_HOME/dots/theme-switch.json" '.to == "artboard" and .ms >= 0 and .ms <= 300'
check "and runs nothing" test ! -e "$DOTS_DEV_DIR/pwned"
DOTS_SWITCH_T0=1000000000000 "$repo/bin/dots" colorscheme catppuccin-mocha
check "a stamp from 2001 is not taken" json_has "$XDG_STATE_HOME/dots/theme-switch.json" '.to == "catppuccin-mocha" and .ms >= 0 and .ms <= 300'
DOTS_SWITCH_T0=9999999999999 "$repo/bin/dots" colorscheme artboard
check "nor one from 2286" json_has "$XDG_STATE_HOME/dots/theme-switch.json" '.to == "artboard" and .ms >= 0 and .ms <= 300'
check "after artboard the fragment's border is Artboard's ink" grep -q 'active-color "#15171B"' "$kdl"
check "GTK prefers light with artboard ($(gtk_scheme))" test "$(gtk_scheme)" = "'prefer-light'"
until_ok 1000 foot_is 255 255 255
check "foot is back on Artboard's surface" foot_is 255 255 255
check "every window still has its id" test "$(windows)" = "$before"
check "the same window keeps focus ($focus_before)" test "$(focused)" = "$focus_before"

exit $((fails > 0))
}
