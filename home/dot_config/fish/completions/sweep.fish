# sweep [-n] [-y] [-d N] [PATH] (user pick 2026-08-08)
complete -c sweep -s n -l dry-run -d 'print what would be deleted, delete nothing'
complete -c sweep -s y -l yes -d 'skip the gum confirm'
complete -c sweep -s d -l days -x -d 'only dirs untouched for N days'
complete -c sweep -s h -l help -d 'usage'
complete -c sweep -x -a '(__fish_complete_directories)'
