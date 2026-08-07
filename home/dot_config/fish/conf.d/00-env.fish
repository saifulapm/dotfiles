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

# Helix runtime, for the kakoune fork's built-in tree-sitter: its Linux
# candidate walk checks /usr/lib/helix/runtime but Fedora installs to lib64,
# so without this every tree-sitter-enable fails "no grammar" (the mac build
# rode a Homebrew fallback path instead). HELIX_RUNTIME is the fork's
# first-priority override (src/main.cc helix_runtime_directory); the custom
# kak/liquid grammars keep coming from ~/.config/helix/runtime, which the
# fork merges in separately. Twin: environment.d/56-helix-runtime.conf.
set -gx HELIX_RUNTIME /usr/lib64/helix/runtime

# Go — XDG-homed like the mac. Source of truth is ~/.config/go/env (go reads
# it in every context — bash scripts, systemd); these exports agree with it
# and just make shells explicit.
set -gx GOPATH "$XDG_DATA_HOME/go"
set -gx GOBIN "$XDG_DATA_HOME/go/bin"

# pnpm
set -gx PNPM_HOME "$HOME/.local/share/pnpm"

# composer — XDG-homed, and pinned: without COMPOSER_HOME composer silently
# prefers a legacy ~/.composer if one exists (a bash script once created it
# and split the global tree off the PATH below). environment.d/55-composer
# carries the same pin for non-shell contexts.
set -gx COMPOSER_HOME "$XDG_CONFIG_HOME/composer"

# Wayland app environment (omarchy envs.lua parity — without it, non-Chromium
# Electron apps silently fall back to XWayland and Qt apps skip the GTK dialog
# theme). Set here, NOT in niri's environment{} block: that block never reaches
# systemd user units (niri docs, Miscellaneous § environment), and qshell — and
# with it the launcher — runs as one. The login shell is the one place both
# niri spawns and systemd services inherit from, via niri-session's import.
#
# GDK_BACKEND is deliberately NOT set (was "wayland,x11,*" from the omarchy
# parity list until 2026-08-08). The comma list is GTK3 syntax; GTK4 takes a
# single backend name, so GTK4 apps matched no backend and fell through to
# XWayland via DISPLAY=:0. That silently broke screen sharing: this env reaches
# xdg-desktop-portal-gnome through niri-session's import-environment, the
# portal saw a non-Wayland GdkDisplay and logged
#
#   GDK backend forced via env var, portal dialogs will not work properly.
#   Non-compatible display server, exposing settings only.
#
# then exported ONLY org.freedesktop.impl.portal.Settings — no ScreenCast — so
# every Chromium/Firefox share died at the portal with "ScreenCastPortal
# failed: 3" long before any GPU work. Unset, GTK4 tries wayland then x11 on
# its own, which is exactly what the old value meant to say, and the portal
# exports all 15 interfaces including ScreenCast (verified 2026-08-08).
# Nothing else here depends on it: Electron rides OZONE_PLATFORM below and the
# Qt dialog theme rides QT_QPA_PLATFORMTHEME.
set -gx QT_QPA_PLATFORM "wayland;xcb"
set -gx QT_QPA_PLATFORMTHEME gtk3
set -gx MOZ_ENABLE_WAYLAND 1
set -gx ELECTRON_OZONE_PLATFORM_HINT wayland
set -gx OZONE_PLATFORM wayland

# PATH — fish_add_path prepends and dedups; safe to re-run every shell.
fish_add_path -g "$HOME/.local/bin"
fish_add_path -g "$HOME/.cargo/bin"
fish_add_path -g "$PNPM_HOME" "$PNPM_HOME/bin"
fish_add_path -g "$HOME/.config/composer/vendor/bin"
fish_add_path -g "$GOBIN"
fish_add_path -g "$HOME/.dotfiles/bin"

# mise shims — node/pnpm/deno for NON-interactive contexts: fish scripts, and
# the login-shell env that niri-session imports into the systemd user manager
# (= what every niri-spawned app inherits; environment.d/50-mise.conf alone
# gets overwritten by that import). Interactive shells layer `mise activate`
# on top (config.fish); its per-directory paths land in front of the shims.
fish_add_path -g "$XDG_DATA_HOME/mise/shims"

# Project-local binaries before global ones (relative on purpose — resolved
# against $PWD, same trick as the mac config). fish_add_path would absolutize
# them, so plain PATH prepend.
set -gx PATH node_modules/.bin vendor/bin $PATH
