# fip <host> <port…> — hosts from ssh config/known_hosts; ports are freeform
# (user pick 2026-08-08)
complete -c fip -f
complete -c fip -x -n '__fish_is_first_token' -a '(__fish_print_hostnames)'
