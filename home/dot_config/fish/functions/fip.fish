# SSH port forwarding: fip starts, dip stops, lip lists (omarchy
# default/bash/fns/ssh-port-forwarding, CREDITS.md).
function fip --description 'Forward local ports over ssh'
    if test (count $argv) -lt 2
        echo "Usage: fip <host> <port1> [port2] ..."
        return 1
    end
    set -l host $argv[1]
    for port in $argv[2..]
        ssh -f -N -L "$port:localhost:$port" $host
        and echo "Forwarding localhost:$port -> $host:$port"
    end
end
