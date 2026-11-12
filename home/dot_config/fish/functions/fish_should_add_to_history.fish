# fish adds a line before it runs, so dots forget's own line, which holds the text it forgets, stays out, as does a history search or delete that checks it; defining this takes over fish's own rule, so a line starting with a space stays out too.
function fish_should_add_to_history
    string match -q ' *' -- $argv[1]; and return 1
    string match -qr '^dots\s+forget(\s|$)' -- $argv[1]; and return 1
    string match -qr '^history\s+(search|delete)(\s|$)' -- $argv[1]; and return 1
    return 0
end
