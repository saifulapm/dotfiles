# Herdr dev layout: editor pane + AI column + bottom terminal — the herdr
# twin of tdl (omarchy default/bash/fns/herdr).
function hdl --description 'Herdr dev layout: editor / ai / terminal'
    if test (count $argv) -eq 0
        echo "Usage: hdl <ai-command> [second-ai-command]"
        return 1
    end
    if not set -q HERDR_PANE_ID
        echo "You must start herdr to use hdl."
        return 1
    end

    set -l current_dir $PWD
    set -l ai $argv[1]
    set -l ai2 $argv[2]
    # HERDR_PANE_ID, not the focused pane: it stays correct if focus moves
    # while the layout is being built.
    set -l editor_pane $HERDR_PANE_ID

    herdr tab rename $HERDR_TAB_ID (basename $current_dir) >/dev/null

    _herdr_split $editor_pane down 0.85 $current_dir >/dev/null
    set -l ai_pane (_herdr_split $editor_pane right 0.7 $current_dir)

    if test -n "$ai2"
        set -l ai2_pane (_herdr_split $ai_pane down 0.5 $current_dir)
        herdr pane run $ai2_pane "$ai2" >/dev/null
    end

    herdr pane run $ai_pane "$ai" >/dev/null
    herdr pane run $editor_pane "$EDITOR ." >/dev/null
end
