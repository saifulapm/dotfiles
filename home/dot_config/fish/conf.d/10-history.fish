# Per-machine fish history (managed by chezmoi).
# Same write-domain idea as the bash side (dot_bashrc.d/20-history.sh): every
# machine writes ONLY its own history file. fish_history is a session name, so
# each machine's file is ~/.local/share/fish/<machine>_history and can never
# conflict across the sync. Session names must be [a-zA-Z0-9_], so the
# machine slug's dashes become underscores (macbook-m2 → macbook_m2).
#
# NOT yet cross-machine-merged: fish's history format is its own (YAML-ish),
# bin/qshell-sync currently moves only the bash-format files, and fish has no
# native "read someone else's file" — follow-up work if wanted.
set -l machine (cat "$HOME/.config/qshell/machine" 2>/dev/null)
test -n "$machine"; or set machine (uname -n)
set -g fish_history (string replace -ra '[^a-zA-Z0-9_]' '_' "$machine")
