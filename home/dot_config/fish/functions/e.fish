function e -d "open file(s) in an Emacs window"
    if functions -q ghostel_cmd; or command -q ghostel_cmd
        ghostel_cmd find-file-other-window $argv
    else
        # No -c/-t: reuses a GUI frame when one is up, and opens a frame on
        # THIS terminal when none is — the usual case here, since ghostel is
        # not installed and the daemon runs frameless. `_emacs_term` is what
        # makes that terminal frame carry the theme's real colors; a GUI frame
        # ignores TERM, so it costs nothing on the other path.
        env TERM=(_emacs_term) emacsclient $argv
    end
end
