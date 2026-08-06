# Environment + PATH (managed by chezmoi). Linux port of the mac zshenv.zsh —
# the homebrew/Herd/DBngin/Java/bun blocks are mac-only and deliberately gone
# (and Bun stays gone everywhere: pnpm, never Bun).

# Editor: kak outside Emacs (mac parity). Inside Emacs, Emacs wires
# with-editor/emacsclient itself — exporting here would clobber that.
# ALTERNATE_EDITOR="" makes emacsclient -a "" auto-start a daemon.
set -gx ALTERNATE_EDITOR ""
if test -z "$INSIDE_EMACS"
    set -gx EDITOR kak
    set -gx VISUAL kak
end

# XDG
set -gx XDG_CACHE_HOME "$HOME/.cache"
set -gx XDG_CONFIG_HOME "$HOME/.config"
set -gx XDG_DATA_HOME "$HOME/.local/share"
set -gx XDG_STATE_HOME "$HOME/.local/state"

# Go — XDG-homed like the mac (future `go install` lands in GOBIN)
set -gx GOPATH "$XDG_DATA_HOME/go"
set -gx GOBIN "$XDG_DATA_HOME/go/bin"

# pnpm
set -gx PNPM_HOME "$HOME/.local/share/pnpm"

# PATH — fish_add_path prepends and dedups; safe to re-run every shell.
fish_add_path -g "$HOME/.local/bin"
fish_add_path -g "$HOME/.cargo/bin"
fish_add_path -g "$PNPM_HOME" "$PNPM_HOME/bin"
fish_add_path -g "$HOME/.config/composer/vendor/bin"
fish_add_path -g "$GOBIN" "$HOME/go/bin"
fish_add_path -g "$HOME/.dotfiles/bin"

# Project-local binaries before global ones (relative on purpose — resolved
# against $PWD, same trick as the mac config). fish_add_path would absolutize
# them, so plain PATH prepend.
set -gx PATH node_modules/.bin vendor/bin $PATH
