# hosts from ssh config/known_hosts; ports are freeform
complete -c fip -f
complete -c fip -x -n '__fish_is_first_token' -a '(__fish_print_hostnames)'
