function gwa -d "new worktree + branch; tmux window or cd into it"
    if test -z "$argv[1]"
        echo "Usage: gwa <branch-name>"
        return 1
    end

    set -l branch $argv[1]
    set -l base (path basename $PWD)
    # feat/projects → feat-projects for the filesystem path
    set -l safe_branch (string replace -a '/' '-' $branch)
    set -l wt_path "../$base--$safe_branch"

    git worktree add -b $branch $wt_path; or return 1

    set -l abs_path (path resolve $wt_path)

    # Seed the worktree's CLAUDE.local.md from the parent repo's hidden
    # template, if present.
    if test -f "$PWD/.CLAUDE.local.md"; and not test -f "$abs_path/CLAUDE.local.md"
        cp "$PWD/.CLAUDE.local.md" "$abs_path/CLAUDE.local.md"
    end

    _gw_spawn_tab $abs_path $branch; or builtin cd $abs_path
end
