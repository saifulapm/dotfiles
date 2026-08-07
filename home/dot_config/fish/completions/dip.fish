# dip <port…> — only ports with an active fip forward make sense here
# (user pick 2026-08-08)
complete -c dip -x -a '(pgrep -af "ssh.*-L [0-9]+:localhost:[0-9]+" 2>/dev/null | string match -agr -- "-L (\d+):")'
