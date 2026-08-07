# One tdl window per subdirectory (omarchy's tdlm).
function tdlm --description 'tdl in a window per subdirectory'
    if test (count $argv) -eq 0
        echo "Usage: tdlm <ai-command> [second-ai-command]"
        return 1
    end
    if not set -q TMUX
        echo "You must start tmux to use tdlm."
        return 1
    end

    set -l base_dir $PWD
    set -l first true

    tmux rename-session (basename $base_dir | tr '.:' '--')

    for dir in $base_dir/*/
        test -d $dir; or continue
        set -l dirpath (string trim -r -c / $dir)
        if test $first = true
            tmux send-keys -t $TMUX_PANE "cd '$dirpath' && tdl $argv" C-m
            set first false
        else
            set -l pane_id (tmux new-window -c $dirpath -P -F '#{pane_id}')
            tmux send-keys -t $pane_id "tdl $argv" C-m
        end
    end
end
