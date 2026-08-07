# Gum styling follows the desktop theme (omarchy gap item 6): bin/theme-apply
# renders ~/.local/state/qshell/gum-theme.fish (a wall of GUM_* set -gx lines,
# omarchy's gum_env.lua port) on every theme change. New shells pick it up;
# running shells keep the palette they started with — same staleness upstream
# has, where the vars ride the compositor environment.
set -l __gum_theme ~/.local/state/qshell/gum-theme.fish
test -f $__gum_theme; and source $__gum_theme
