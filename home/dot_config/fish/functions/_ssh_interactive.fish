# True for an interactive SSH session: exactly one destination and no remote
# command. Used to decide whether a dropped connection may be replayed — a
# remote command must never run twice behind the user's back.
function _ssh_interactive --description 'Is this ssh invocation an interactive session?'
    # The ssh(1) options that consume a value, so their arguments are not
    # mistaken for the destination.
    set -l value_opts (string split '' -- BbcDEeFIiJLlmOoPpQRSWw)
    set -l dest ""
    set -l opts_done 0
    set -l i 1
    set -l n (count $argv)

    while test $i -le $n
        set -l arg $argv[$i]
        set i (math $i + 1)

        if test $opts_done -eq 0; and test "$arg" = "--"
            set opts_done 1
        else if test $opts_done -eq 0; and string match -qr -- '^-.+' $arg
            set -l letters (string split '' -- (string sub -s 2 -- $arg))
            set -l len (count $letters)
            for j in (seq 1 $len)
                if contains -- $letters[$j] $value_opts
                    # The value is glued to the letter (-p2222) unless the
                    # letter ends the argument, where it takes the next one.
                    test $j -eq $len; and set i (math $i + 1)
                    break
                end
            end
        else if test -z "$dest"
            set dest $arg
        else
            # A second positional is a remote command.
            return 1
        end
    end

    test -n "$dest"; or return 1

    # A RemoteCommand from ssh_config or -o replays on reconnect just like a
    # positional command; `ssh -G` resolves the effective configuration for
    # this exact invocation without connecting. Fail closed when it resolves
    # nothing, since an undetected RemoteCommand must not replay. An explicit
    # "none" cancels a configured command, and some versions emit it when
    # unset.
    set -l resolved (command ssh -G $argv 2>/dev/null)
    test (count $resolved) -gt 0; or return 1

    for line in $resolved
        if string match -qri -- '^remotecommand ' $line
            string match -qri -- '^remotecommand none$' $line; or return 1
        end
    end
    return 0
end
