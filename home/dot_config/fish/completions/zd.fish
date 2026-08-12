# zd — the cd wrapper: complete like cd (real directories, CDPATH aware);
# non-directory queries fall through to zoxide at runtime (user pick 2026-08-08)
#
# __fish_complete_cd alone is NOT directory completion — since fish 4 it is only
# a CDPATH helper and returns immediately when CDPATH is unset (which it is
# here), so `-x -a '(__fish_complete_cd)'` produced ZERO candidates: -x kills
# fish's core file completion and the helper supplied nothing. Stock cd.fish
# gets away with the same -a because it omits -x and lets the core completion
# do the work. Use __fish_complete_directories instead: it is the real
# directory-only completer, so `cd ~/Site<Tab>` → `~/Sites/` again. Keep -x —
# with this completer it excludes plain files, which zd can't cd into anyway.
# `alias cd zd` makes cd a --wraps=zd function, so cd inherits this. (2026-08-12)
complete -c zd -k -x -a '(__fish_complete_directories)'
