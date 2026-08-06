function gwl -d "pick a worktree with fzf and switch to it"
    git rev-parse --show-toplevel >/dev/null 2>&1; or begin
        echo "Not in a git repo"
        return 1
    end

    set -l selected (git worktree list --porcelain \
        | awk '/^worktree /{print substr($0,10)}' \
        | fzf --preview 'git -C {} log --oneline -n 15 2>/dev/null' \
              --preview-window 'right:60%' \
              --header 'Enter: switch')
    test -z "$selected"; and return 0

    set -l name (string replace -r '^.*?--' '' (path basename $selected))
    _gw_spawn_tab $selected $name; or builtin cd $selected
end
