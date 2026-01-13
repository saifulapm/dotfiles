# If not running interactively, don't do anything
[[ $- != *i* ]] && return

# Dotfiles shell config
SHELL_CONFIG="$HOME/.config/shell"

[[ -f "$SHELL_CONFIG/options" ]]   && source "$SHELL_CONFIG/options"
[[ -f "$SHELL_CONFIG/envs" ]]      && source "$SHELL_CONFIG/envs"
[[ -f "$SHELL_CONFIG/aliases" ]]   && source "$SHELL_CONFIG/aliases"
[[ -f "$SHELL_CONFIG/functions" ]] && source "$SHELL_CONFIG/functions"
[[ -f "$SHELL_CONFIG/init" ]]      && source "$SHELL_CONFIG/init"

# Readline config
[[ -f "$SHELL_CONFIG/inputrc" ]] && bind -f "$SHELL_CONFIG/inputrc"

# Local overrides (not tracked in git)
[[ -f ~/.bashrc.local ]] && source ~/.bashrc.local
