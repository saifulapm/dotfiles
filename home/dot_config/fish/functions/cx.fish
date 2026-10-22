# Claude Code in the active account's home, as dots claude-account keeps it; the main account uses the default home.
function cx
    set -l state $HOME/.local/state
    set -q XDG_STATE_HOME; and set state $XDG_STATE_HOME
    set -l reg $state/dots/claude-accounts.json
    set -l dir
    test -f $reg; and set dir (jq -r '.active as $a | .accounts[] | select(.id == $a) | .home' $reg 2>/dev/null)
    if test -n "$dir" -a "$dir" != "$HOME/.claude"
        env CLAUDE_CONFIG_DIR=$dir claude --allow-dangerously-skip-permissions $argv
    else
        claude --allow-dangerously-skip-permissions $argv
    end
end
