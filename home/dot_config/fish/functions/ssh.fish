# A remote tmux or editor arms terminal modes that only it can disarm. When the connection dies instead of exiting, they stay armed locally (see _ssh_disarm), so this wrapper cleans up and reconnects.
# ServerAliveInterval in ~/.ssh/config is the other half: without it ssh does not notice a dead connection until TCP gives up.
function ssh --description 'ssh, with terminal cleanup and reconnect on drop'
    set -l started (date +%s)
    command ssh $argv
    set -l rc $status
    set -l elapsed (math (date +%s) - $started)

    isatty stdout; or return $rc
    _ssh_disarm

    # Reconnect only when an interactive session drops. ssh exits 255 for
    # transport failures, but a fast 255 with no established session is a
    # connect/auth failure; a remote command's own 255 passes through
    # indistinguishably and must not replay its side effects; and redirected
    # stdin would feed the rest of the piped input to a fresh remote shell.
    if test $rc -ne 255; or not isatty stdin; or not _ssh_interactive $argv; or test $elapsed -lt 30
        return $rc
    end

    # Fast failures retry too, since a rebooting server refuses connections
    # before it accepts them again. Ctrl-C makes ssh exit 130 (not 255) and
    # interrupts the pause, and both break out below.
    while true
        echo "Connection lost. Reconnecting (Ctrl-C to stop)..."
        sleep 2; or break
        command ssh $argv
        set rc $status
        _ssh_disarm
        test $rc -ne 255; and break
    end

    return $rc
end
