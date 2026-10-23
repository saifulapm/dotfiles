# niri-session re-execs through a non-interactive login shell, so without the interactive test this would recurse.
if status is-login; and status is-interactive; and test -z "$WAYLAND_DISPLAY"; and test (tty) = /dev/tty1
    exec niri-session
end
set -g fish_greeting

set -gx EDITOR kak
set -gx VISUAL kak
set -gx HELIX_RUNTIME /usr/lib64/helix/runtime
# Without it composer prefers a legacy ~/.composer when one exists.
set -gx COMPOSER_HOME ~/.config/composer

set -gx GOPATH ~/.local/share/go
set -gx GOBIN $GOPATH/bin
set -gx PNPM_HOME ~/.local/share/pnpm
set -gx ANDROID_HOME ~/Android/Sdk

# fish_add_path skips a directory that does not exist, so a machine without the tool gets nothing.
fish_add_path -g ~/.local/bin ~/.config/composer/vendor/bin ~/Codes/dotfiles/bin ~/.cargo/bin $PNPM_HOME $PNPM_HOME/bin $GOBIN $ANDROID_HOME/platform-tools $ANDROID_HOME/cmdline-tools/latest/bin $ANDROID_HOME/emulator ~/.local/share/mise/shims
# Last, so an untrusted clone cannot shadow a system command with its own node_modules/.bin or vendor/bin; fish_add_path would make them absolute.
set -gx PATH $PATH node_modules/.bin vendor/bin

set -g __dots_colors_file (set -q XDG_STATE_HOME; and echo $XDG_STATE_HOME; or echo ~/.local/state)/dots/theme-out/colors.fish
# dots theme rewrites the colours file, so each prompt re-reads it once its text changes.
function __dots_colors --on-event fish_prompt
    test -r $__dots_colors_file; or return
    set -l text (string collect <$__dots_colors_file 2>/dev/null); or return
    test "$text" = "$__dots_colors_seen"; and return
    set -g __dots_colors_seen $text
    source $__dots_colors_file
end
__dots_colors

# gpg asks for a passphrase on this terminal; over SSH, dots-pinentry reads PINENTRY_USER_DATA and draws curses instead of a card on the far screen.
isatty stdin; and set -gx GPG_TTY (tty)
set -q SSH_CONNECTION; and set -gx PINENTRY_USER_DATA curses

if status is-interactive
    command -q mise; and mise activate fish | source
    command -q zoxide; and zoxide init fish | source
end
