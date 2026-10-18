set -g fish_greeting
fish_add_path -g ~/Sites/github/dotfiles/bin
set -g __dots_colors_file (set -q XDG_STATE_HOME; and echo $XDG_STATE_HOME; or echo ~/.local/state)/dots/theme-out/colors.fish
# dots theme rewrites the colours file, so each prompt re-reads it once its text changes.
function __dots_colors --on-event fish_prompt
    set -l text (string collect <$__dots_colors_file 2>/dev/null); or return
    test "$text" = "$__dots_colors_seen"; and return
    set -g __dots_colors_seen $text
    source $__dots_colors_file
end
__dots_colors
