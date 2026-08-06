function d -d "open a directory in dired (defaults to cwd)"
    set -l target $argv[1]
    test -n "$target"; or set target $PWD
    if functions -q ghostel_cmd; or command -q ghostel_cmd
        ghostel_cmd dired $target
    else
        emacsclient --eval "(dired \"$target\")" >/dev/null
    end
end
