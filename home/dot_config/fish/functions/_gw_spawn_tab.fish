# Linux port of the mac helper: the mac spawned wezterm/ghostty tabs, but foot
# has no tabs — tmux windows are the only spawn target here. Returns 1 when it
# spawned nothing, so callers fall back to a plain cd.
function _gw_spawn_tab -a cwd title
    if test -n "$TMUX"; and command -q tmux
        tmux new-window -c "$cwd" -n "$title" >/dev/null; and return 0
    end
    return 1
end
