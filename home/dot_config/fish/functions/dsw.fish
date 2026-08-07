function dsw --description 'Stop rsync-on-change watchers'
    set -l pids (pgrep -f 'rsw-watch ')
    if test (count $pids) -eq 0
        echo "No active watches"
        return
    end
    for pid in $pids
        kill -- -$pid 2>/dev/null
        and echo "Stopped watch (pid $pid)"
    end
end
