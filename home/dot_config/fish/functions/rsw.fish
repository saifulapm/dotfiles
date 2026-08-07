# Rsync-on-change watchers: rsw starts one detached, lsw lists, dsw stops
# (omarchy default/bash/fns/rsyncing, CREDITS.md). The watch loop itself
# stays a bash one-liner — setsid + inotifywait pipelines are what bash is
# for — and one SSH ControlMaster socket per host keeps auth to one prompt.
function rsw --description 'Mirror a directory on every change'
    if test (count $argv) -ne 2
        echo "Usage: rsw <source> <destination>"
        return 1
    end
    set -l src (string trim -r -c / $argv[1])
    set -l dest $argv[2]
    set -l sockets $XDG_RUNTIME_DIR
    test -n "$sockets"; or set sockets $HOME/.ssh/sockets
    mkdir -p $sockets
    set -l rsh "ssh -o ControlMaster=auto -o ControlPath=$sockets/rsw-%r@%h:%p -o ControlPersist=yes"
    setsid --fork env RSYNC_RSH="$rsh" bash -c 'rsync -a "$1/" "$2"; while inotifywait -r -q -e modify,create,delete,move "$1"; do rsync -a "$1/" "$2"; done' rsw-watch $src $dest >/dev/null 2>&1
    echo "Watching $src -> $dest"
end
