# foot has no tabs, so a tmux window is the only spawn target. Returns 1 when it spawned nothing, so callers fall back to a plain cd.
function _gw_spawn_tab -a cwd title
    if test -n "$TMUX"; and command -q tmux
        tmux new-window -c "$cwd" -n "$title" >/dev/null; and return 0
    end
    return 1
end
