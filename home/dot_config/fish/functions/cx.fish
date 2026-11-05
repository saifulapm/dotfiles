# Claude Code in the active account, through the wrapper every launcher runs: it reads dots claude-account's registry, and the main account uses the default home.
function cx --wraps claude --description 'Claude Code in the active account'
    ~/.local/libexec/dots/claude --allow-dangerously-skip-permissions $argv
end
