function gwa -d "new worktree + branch; tmux window or cd into it"
    if test -z "$argv[1]"
        echo "Usage: gwa <branch-name>"
        return 1
    end

    set -l branch $argv[1]
    set -l base (path basename $PWD)
    # feat/projects becomes feat-projects for the filesystem path
    set -l safe_branch (string replace -a '/' '-' $branch)
    set -l wt_path "../$base--$safe_branch"

    git worktree add -b $branch $wt_path; or return 1

    _gw_spawn_tab (path resolve $wt_path) $branch; or builtin cd (path resolve $wt_path)
end
