# Tmux dev square: editor / live diff / terminal / AI (omarchy's tds;
# their nvim+hunk+opencode hardcodes swapped for what this machine runs —
# $EDITOR, watchexec-driven git diff, claude).
function tds --description 'Tmux dev square: editor / diff / terminal / ai'
    if test (count $argv) -gt 1
        echo "Usage: tds [ai-command]"
        return 1
    end
    if not set -q TMUX
        echo "You must start tmux to use tds."
        return 1
    end

    set -l current_dir $PWD
    set -l ai claude
    test -n "$argv[1]"; and set ai $argv[1]
    set -l editor_pane $TMUX_PANE

    tmux rename-window -t $editor_pane (basename $current_dir)
    set -l terminal_pane (tmux split-window -v -p 50 -t $editor_pane -c $current_dir -P -F '#{pane_id}')
    set -l diff_pane (tmux split-window -h -p 50 -t $editor_pane -c $current_dir -P -F '#{pane_id}')
    set -l ai_pane (tmux split-window -h -p 50 -t $terminal_pane -c $current_dir -P -F '#{pane_id}')

    tmux send-keys -t $editor_pane -l "$EDITOR ."
    tmux send-keys -t $editor_pane C-m
    tmux send-keys -t $diff_pane -l 'watchexec --no-project-ignore -c -- git --no-pager diff --stat'
    tmux send-keys -t $diff_pane C-m
    tmux send-keys -t $ai_pane -l "$ai"
    tmux send-keys -t $ai_pane C-m

    tmux select-pane -t $editor_pane
end
