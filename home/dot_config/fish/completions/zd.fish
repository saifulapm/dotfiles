# Directory-only, like cd; since fish 4 __fish_complete_cd is only a CDPATH helper and gives nothing here.
complete -c zd -k -x -a '(__fish_complete_directories)'
