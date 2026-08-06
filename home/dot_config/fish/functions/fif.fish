function fif -d "find-in-files: rg matches piped to fzf with context preview"
    if test (count $argv) -eq 0
        echo "Need a string to search for!"
        return 1
    end
    rg --files-with-matches --no-messages "$argv[1]" \
        | fzf --preview "rg --ignore-case --pretty --context 10 '$argv[1]' {}"
end
