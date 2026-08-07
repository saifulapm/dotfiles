# gws <query> — worktree basenames; gws itself fuzzy-greps the full path,
# so any completed basename matches (user pick 2026-08-08)
complete -c gws -x -a '(git worktree list --porcelain 2>/dev/null | string replace -f "worktree " "" | path basename)'
