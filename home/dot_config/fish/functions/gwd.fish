function gwd -d "remove current worktree and its branch, once confirmed"
    set -l cwd (pwd)

    git rev-parse --show-toplevel >/dev/null 2>&1; or begin
        echo "Not in a git repo"
        return 1
    end

    # The primary worktree is the first entry in the list
    set -l main_wt (git worktree list --porcelain | awk '/^worktree /{print substr($0,10); exit}')
    if test "$cwd" = "$main_wt"
        echo "Refusing to delete the primary worktree"
        return 1
    end

    set -l branch (git branch --show-current)
    if test -z "$branch"
        echo "Detached HEAD — can't determine branch"
        return 1
    end

    read -l -P "Remove worktree '$cwd' and branch '$branch'? [y/N] " answer
    if string match -qi y -- $answer
        builtin cd $main_wt; or return 1
        git worktree remove $cwd --force; or return 1
        git branch -D $branch; or return 1
        echo "✓ removed"
    end
end
