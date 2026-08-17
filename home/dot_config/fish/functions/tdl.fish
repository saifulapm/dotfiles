# Tmux dev layout: editor pane + AI column + bottom terminal (omarchy
# default/bash/fns/tmux; their stray $opencode_pane select
# fixed — focus lands on the editor).
function tdl --description 'Tmux dev layout: editor / ai / terminal'
    if test (count $argv) -eq 0
        echo "Usage: tdl <ai-command> [second-ai-command]"
        return 1
    end
    if not set -q TMUX
        echo "You must start tmux to use tdl."
        return 1
    end

    set -l current_dir $PWD
    set -l ai $argv[1]
    set -l ai2 $argv[2]
    set -l editor_pane $TMUX_PANE

    tmux rename-window -t $editor_pane (basename $current_dir)
    tmux split-window -v -p 15 -t $editor_pane -c $current_dir
    set -l ai_pane (tmux split-window -h -p 30 -t $editor_pane -c $current_dir -P -F '#{pane_id}')

    if test -n "$ai2"
        set -l ai2_pane (tmux split-window -v -t $ai_pane -c $current_dir -P -F '#{pane_id}')
        tmux send-keys -t $ai2_pane "$ai2" C-m
    end

    tmux send-keys -t $ai_pane "$ai" C-m
    tmux send-keys -t $editor_pane "$EDITOR ." C-m
    tmux select-pane -t $editor_pane
end
