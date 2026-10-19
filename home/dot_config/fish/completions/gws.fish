# gws fuzzy-greps the full path, so any completed basename matches
complete -c gws -x -a '(git worktree list --porcelain 2>/dev/null | string replace -f "worktree " "" | path basename)'
