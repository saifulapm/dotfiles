# zd — the cd wrapper: complete like cd (real directories, CDPATH aware);
# non-directory queries fall through to zoxide at runtime (user pick 2026-08-08)
complete -c zd -k -x -a '(__fish_complete_cd)'
