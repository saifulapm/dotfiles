# radio [subcommand|station] — station names come from the same file the
# script reads, parsed the same way it parses them (drop comments and blanks,
# take the field before the tab).
function __qshell_radio_stations
    set -l dir $XDG_CONFIG_HOME
    test -n "$dir"; or set dir $HOME/.config
    set -l file $dir/qshell/radio-stations
    test -f $file; or return
    grep -v '^[[:space:]]*#' $file | string match -v -r '^\s*$' | cut -f1
end

complete -c radio -f
complete -c radio -n __fish_use_subcommand -a '(__qshell_radio_stations)' -d Station
complete -c radio -n __fish_use_subcommand -a search -d 'Search radio-browser.info for a station'
complete -c radio -n __fish_use_subcommand -a play -d 'Play a stream URL'
complete -c radio -n __fish_use_subcommand -a save -d 'Save the playing station'
complete -c radio -n __fish_use_subcommand -a toggle -d 'Pause, resume, or pick a station'
complete -c radio -n __fish_use_subcommand -a stop -d 'Stop playback'
complete -c radio -n __fish_use_subcommand -a status -d 'Print the current station'
complete -c radio -n __fish_use_subcommand -a list -d 'Print the saved stations'
