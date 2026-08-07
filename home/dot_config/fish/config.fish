# fish config (managed by chezmoi — edit in ~/.dotfiles/home/dot_config/fish/)
# Port of the mac zsh setup (iCloud .dotfiles/config/zsh), 2026-08-07.
# Env/PATH/aliases live in conf.d/*.fish (fish sources those BEFORE this file);
# functions autoload from functions/. Machine-local overrides (secrets):
# conf.d/99-local.fish, deliberately NOT chezmoi-managed.

# ─── niri on tty1 ────────────────────────────────────────────────────────────
# Autologin lands a login shell here (see run_before_01-autologin.sh.tmpl).
# This block replaces .bash_profile's launcher — with fish as the login shell,
# bash startup files never run. The is-interactive guard is load-bearing:
# niri-session re-execs itself through a NON-interactive login shell, and fish
# sources config.fish for every shell, so without it the exec recurses.
if status is-login
    and status is-interactive
    and test -z "$WAYLAND_DISPLAY"
    and test (tty) = /dev/tty1
    and not systemctl --user -q is-active niri.service 2>/dev/null
    exec niri-session
end

# ─── interactive setup ───────────────────────────────────────────────────────
# A guard block, NOT an early `exit` — exit in config.fish terminates the
# shell before a `fish -c`/`fish -l -c` command ever runs, which would break
# every script (and niri-session's own re-exec) that invokes fish
# non-interactively.
if status is-interactive
    set -g fish_greeting ""

    # mise: node/deno version manager (activate > shims — updates env per dir)
    if command -q mise
        mise activate fish | source
    end

    # Prompt, directory jumper, television fuzzy finder
    command -q starship; and starship init fish | source
    command -q zoxide; and zoxide init fish | source
    command -q tv; and tv init fish | source
end
