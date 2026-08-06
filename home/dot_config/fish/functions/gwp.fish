function gwp -d "sweep worktrees whose branch is merged into main"
    git rev-parse --show-toplevel >/dev/null 2>&1; or begin
        echo "Not in a git repo"
        return 1
    end

    # Detect main branch: origin/HEAD → local main → local master
    set -l main (git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | string replace 'refs/remotes/origin/' '')
    if test -z "$main"
        if git show-ref --verify --quiet refs/heads/main
            set main main
        else if git show-ref --verify --quiet refs/heads/master
            set main master
        else
            echo "Can't detect main branch"
            return 1
        end
    end

    # Compare against origin/$main when it exists, else local
    set -l base $main
    git show-ref --verify --quiet "refs/remotes/origin/$main"; and set base "origin/$main"

    set -l current (git branch --show-current 2>/dev/null)

    echo "Pruning stale worktree entries…"
    git worktree prune

    echo "Comparing branches against '$base'…"
    set -l any 0
    set -l wt_path ""

    for line in (git worktree list --porcelain)
        switch $line
            case 'worktree *'
                set wt_path (string sub -s 10 -- $line)
            case 'branch refs/heads/*'
                set -l wt_branch (string replace 'branch refs/heads/' '' -- $line)
                # Skip main and the checked-out branch (can't remove either)
                if test "$wt_branch" != "$main"; and test "$wt_branch" != "$current"
                    if git merge-base --is-ancestor $wt_branch $base 2>/dev/null
                        set any 1
                        echo ""
                        echo "→ worktree:  $wt_path"
                        echo "  branch:    $wt_branch (merged into $base)"
                        if gum confirm "Remove?"
                            git worktree remove $wt_path --force
                            and git branch -D $wt_branch
                            and echo "  ✓ removed"
                        end
                    end
                end
            case ''
                set wt_path ""
        end
    end

    test $any -eq 0; and echo "Nothing to prune."
end
