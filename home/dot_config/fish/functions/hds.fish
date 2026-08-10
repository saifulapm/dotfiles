# Herdr dev square: editor / live diff / terminal / AI — the herdr twin of
# tds, with the same substitutions that one makes for what this machine
# actually runs ($EDITOR, watchexec-driven git diff, claude) in place of
# omarchy's nvim/hunk/opencode.
function hds --description 'Herdr dev square: editor / diff / terminal / ai'
    if test (count $argv) -gt 1
        echo "Usage: hds [ai-command]"
        return 1
    end
    if not set -q HERDR_PANE_ID
        echo "You must start herdr to use hds."
        return 1
    end

    set -l current_dir $PWD
    set -l ai claude
    test -n "$argv[1]"; and set ai $argv[1]
    set -l editor_pane $HERDR_PANE_ID

    herdr tab rename $HERDR_TAB_ID (basename $current_dir) >/dev/null

    set -l terminal_pane (_herdr_split $editor_pane down 0.5 $current_dir)
    set -l diff_pane (_herdr_split $editor_pane right 0.5 $current_dir)
    set -l ai_pane (_herdr_split $terminal_pane right 0.5 $current_dir)

    herdr pane run $editor_pane "$EDITOR ." >/dev/null
    herdr pane run $diff_pane 'watchexec --no-project-ignore -c -- git --no-pager diff --stat' >/dev/null
    herdr pane run $ai_pane "$ai" >/dev/null
end
