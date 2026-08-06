function mg -d "magit-status for a directory (defaults to cwd)"
    set -l target $argv[1]
    test -n "$target"; or set target $PWD
    if functions -q ghostel_cmd; or command -q ghostel_cmd
        ghostel_cmd magit $target
    else
        emacsclient --eval "(magit-status \"$target\")" >/dev/null
    end
end
