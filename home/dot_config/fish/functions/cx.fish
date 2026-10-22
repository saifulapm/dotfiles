# Claude Code in the active account's home, as dots claude-account keeps it; the main account uses the default home.
function cx --wraps claude --description 'Claude Code in the active account'
    set -l state $HOME/.local/state
    set -q XDG_STATE_HOME; and set state $XDG_STATE_HOME
    set -l reg $state/dots/claude-accounts.json
    set -l dir
    test -f $reg; and set dir (jq -r '.active as $a | first(.accounts[] | select(.id == $a)) | .home // "-"' $reg 2>/dev/null)
    # An active account with no home, or one gone, would give claude a fresh, logged-out config dir.
    if test -n "$dir"; and not test -d "$dir"
        echo "cx: the active Claude account's home is missing; dots claude-account use main goes back to the main one" >&2
        return 1
    end
    if test -n "$dir" -a "$dir" != "$HOME/.claude"
        env CLAUDE_CONFIG_DIR=$dir claude --allow-dangerously-skip-permissions $argv
    else
        env -u CLAUDE_CONFIG_DIR claude --allow-dangerously-skip-permissions $argv
    end
end
