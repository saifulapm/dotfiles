# try [clone <url> [name]] | try <name> (user pick 2026-08-08)
complete -c try -f
complete -c try -n '__fish_use_subcommand' -a clone -d 'git clone into a dated dir under ~/Sites/tries'
