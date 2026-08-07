# power-profile [autodetect|ac|battery] [profile] | list (user pick 2026-08-08)
# Profiles offered are whatever `power-profile list` reports live — the
# machine decides whether `performance` exists, not this file.
complete -c power-profile -x -n '__fish_is_first_token' -a 'autodetect ac battery list'
complete -c power-profile -x -n '__fish_is_first_token' -a '(power-profile list 2>/dev/null)'
complete -c power-profile -x -n 'not __fish_is_first_token' -a '(power-profile list 2>/dev/null)'
