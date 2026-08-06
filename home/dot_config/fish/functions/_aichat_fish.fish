function _aichat_fish -d "Alt-e: replace the command line with aichat -e output"
    set -l _old (commandline)
    test -n "$_old"; or return
    commandline -r (aichat -e "$_old" | string collect)
    commandline -f end-of-line repaint
end
