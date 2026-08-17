# Wrap ssh to clean up the terminal and reconnect when a connection drops
# (omarchy default/bash/fns/ssh-reconnect — fish port).
#
# A remote tmux, herdr or editor arms terminal modes over the SSH pipe that
# only it can disarm. If the connection dies instead of exiting cleanly, those
# modes stay armed on the local terminal (see _ssh_disarm). The keepalives in
# ~/.ssh/config are the other half: without them ssh does not notice a dead
# connection until TCP gives up, so there is nothing to clean up after until
# the hang is over.
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

    # Keep retrying fast failures too — a rebooting server refuses
    # connections before it starts accepting them again. Ctrl-C stops the
    # loop: it makes ssh exit 130 (not 255) and interrupts the pause, and
    # both of those break out below.
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
