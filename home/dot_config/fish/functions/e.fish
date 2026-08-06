function e -d "open file(s) in an Emacs window"
    if functions -q ghostel_cmd; or command -q ghostel_cmd
        ghostel_cmd find-file-other-window $argv
    else
        emacsclient $argv
    end
end
