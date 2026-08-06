# Cross-machine shell history — the per-device write-domain pattern
# (omarchy's sync invariant, CREDITS.md): every machine appends ONLY to its
# own history file inside the synced folder and reads the union, so three
# machines can never conflict. bin/qshell-sync moves the folder through the
# Dropbox hub on a timer; this file is the bash side of the contract.
#
# ~/.config/qshell/machine is written by chezmoi from the machine prompt —
# the hostname is NOT unique across these boxes (every Asahi install answers
# "fedora"), which is why it cannot be the file name.

_qshell_histdir="$HOME/.local/state/qshell/sync/history"
_qshell_machine="$(cat "$HOME/.config/qshell/machine" 2>/dev/null)"
[ -n "$_qshell_machine" ] || _qshell_machine="$(uname -n)"
mkdir -p "$_qshell_histdir"

# Seed once from the pre-sync history, so day one starts with the past.
if [ ! -f "$_qshell_histdir/$_qshell_machine.history" ] && [ -f "$HOME/.bash_history" ]; then
  cp "$HOME/.bash_history" "$_qshell_histdir/$_qshell_machine.history"
fi

HISTFILE="$_qshell_histdir/$_qshell_machine.history"
HISTSIZE=100000
HISTFILESIZE=200000
HISTCONTROL=ignoreboth
# Epoch stamps in the file — they survive the trip between machines and keep
# a merged C-r roughly chronological.
HISTTIMEFORMAT='%F %T '
shopt -s histappend
# Append after every command, not only at exit: a crashed or long-lived
# session must not hold hours of history hostage from the sync.
PROMPT_COMMAND="history -a${PROMPT_COMMAND:+; $PROMPT_COMMAND}"

# The other machines' files, read-only, into this session's list. Bash loads
# $HISTFILE itself after the rc files run, so our own entries land on top.
for _qshell_hist in "$_qshell_histdir"/*.history; do
  [ -f "$_qshell_hist" ] || continue
  [ "$_qshell_hist" = "$HISTFILE" ] && continue
  history -r "$_qshell_hist"
done
unset _qshell_hist _qshell_histdir _qshell_machine
