# forgit — interactive git with fzf (ga, glo, gd, gcb …). The mac loaded it
# through sheldon (zsh); fish sources the plugin's own fish port directly from
# the chezmoi external at ~/.local/share/forgit (pinned 26.01.0, the same rev
# the mac pinned). Syntax highlighting and autosuggestions, sheldon's other
# jobs, are fish built-ins and need nothing here.
set -l forgit "$HOME/.local/share/forgit/conf.d/forgit.plugin.fish"
test -r "$forgit"; and source "$forgit"
