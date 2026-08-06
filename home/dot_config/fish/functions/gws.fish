function gws -a query -d "switch to worktree by fuzzy name match"
    if test -z "$query"
        gwl
        return
    end

    set -l match (git worktree list --porcelain \
        | awk '/^worktree /{print substr($0,10)}' \
        | grep -i -- "$query" | head -1)
    if test -z "$match"
        echo "No worktree matching '$query'"
        return 1
    end

    set -l name (string replace -r '^.*?--' '' (path basename $match))
    _gw_spawn_tab $match $name; or builtin cd $match
end
