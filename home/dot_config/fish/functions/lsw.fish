function lsw --description 'List rsync-on-change watchers'
    set -l lines (pgrep -af 'rsw-watch ')
    if test (count $lines) -eq 0
        echo "No active watches"
        return
    end
    for line in $lines
        set -l pid (string split -m1 ' ' -- $line)[1]
        set -l parts (string split ' ' -- (string replace -r '.*rsw-watch ' '' -- $line))
        echo "$pid: $parts[1] -> $parts[2]"
    end
end
