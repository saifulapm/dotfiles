# aichat — completions, VENDORED from upstream (sigoden/aichat, tag v0.30.0,
# scripts/completions/aichat.fish) rather than generated.
#
# aichat has no `completion <shell>` verb: upstream keeps hand-maintained
# scripts per shell in that directory and expects you to copy the one you
# want. So there is nothing for run_after_23's generate-and-`fish -n` gate to
# drive here — this is a static file, checked with `fish -n` once at the
# commit that added it (2026-09-06).
#
# The mac dotfiles carried the ZSH half of this instead (config/zsh/aichat.zsh
# was the Alt-e zle widget plus a compdef block); fish's equivalent is this
# file plus functions/_aichat_fish.fish.
#
# It stays DYNAMIC on purpose — model, role, session, agent, rag and macro
# names come from `aichat --list-*` at completion time, so they follow the
# config instead of drifting. With this repo's pxy-only client that means
# `-m <TAB>` offers pxy's five routing groups.
#
# Re-copy from upstream after an aichat upgrade if the flag set changes.
complete -c aichat -s m -l model -x -a "(aichat --list-models)" -d 'Select a LLM model' -r
complete -c aichat -l prompt -d 'Use the system prompt'
complete -c aichat -s r -l role -x -a "(aichat --list-roles)" -d 'Select a role' -r
complete -c aichat -s s -l session -x  -a "(aichat --list-sessions)" -d 'Start or join a session' -r
complete -c aichat -l empty-session -d 'Ensure the session is empty'
complete -c aichat -l save-session -d 'Ensure the new conversation is saved to the session'
complete -c aichat -s a -l agent -x  -a "(aichat --list-agents)" -d 'Start a agent' -r
complete -c aichat -l agent-variable -d 'Set agent variables'
complete -c aichat -l rag -x  -a"(aichat --list-rags)" -d 'Start a RAG' -r
complete -c aichat -l rebuild-rag -d 'Rebuild the RAG to sync document changes'
complete -c aichat -l macro -x  -a"(aichat --list-macros)" -d 'Execute a macro' -r
complete -c aichat -l serve -d 'Serve the LLM API and WebAPP'
complete -c aichat -s e -l execute -d 'Execute commands in natural language'
complete -c aichat -s c -l code -d 'Output code only'
complete -c aichat -s f -l file -d 'Include files, directories, or URLs' -r -F
complete -c aichat -s S -l no-stream -d 'Turn off stream mode'
complete -c aichat -l dry-run -d 'Display the message without sending it'
complete -c aichat -l info -d 'Display information'
complete -c aichat -l sync-models -d 'Sync models updates'
complete -c aichat -l list-models -d 'List all available chat models'
complete -c aichat -l list-roles -d 'List all roles'
complete -c aichat -l list-sessions -d 'List all sessions'
complete -c aichat -l list-agents -d 'List all agents'
complete -c aichat -l list-rags -d 'List all RAGs'
complete -c aichat -l list-macros -d 'List all macros'
complete -c aichat -s h -l help -d 'Print help'
complete -c aichat -s V -l version -d 'Print version'
