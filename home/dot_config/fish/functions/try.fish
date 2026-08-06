function try -d "fresh directories for every vibe (~/Sites/tries)"
    set -l dir "$HOME/Sites/tries"
    test -n "$TRY_PATH"; and set dir $TRY_PATH
    mkdir -p $dir

    if test "$argv[1]" = clone; and test -n "$argv[2]"
        set -l name $argv[3]
        test -z "$name"; and set name (string replace -r '\.git$' '' (path basename $argv[2]))
        set -l target "$dir/"(date +%Y-%m-%d)"-$name"
        git clone $argv[2] $target; and builtin cd $target
        return
    end

    if test -n "$argv[1]"
        set -l target "$dir/"(date +%Y-%m-%d)"-$argv[1]"
        mkdir -p $target; and builtin cd $target
        return
    end

    # --print-query: line 1 is the query, line 2 (if any) the selection
    set -l out (fd -t d --max-depth 1 . $dir --exec basename {} | sort -r \
        | fzf --preview "lsd -la --color=always $dir/{}" --print-query \
              --bind "ctrl-n:print-query+abort")
    set -l query $out[1]
    set -l match $out[2]

    if test -n "$match"
        builtin cd "$dir/$match"
    else if test -n "$query"
        try $query
    end
end
