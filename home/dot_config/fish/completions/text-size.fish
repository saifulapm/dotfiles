# text-size — the desktop text-size knob (user pick 2026-08-08)
complete -c text-size -x -a '(seq 9 20)'
complete -c text-size -x -a reset -d 'drop the override, back to the theme size'
complete -c text-size -l value -d 'print just the effective integer'
