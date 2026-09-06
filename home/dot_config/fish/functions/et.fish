function et -d "terminal Emacs via the running daemon"
    # `_emacs_term` upgrades TERM to the direct-color terminfo entry, without
    # which the frame paints the qshell theme in 256-color approximations.
    env TERM=(_emacs_term) emacsclient -t $argv
end
