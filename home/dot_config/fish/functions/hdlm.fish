# One hdl tab per subdirectory of the current directory — the herdr twin of
# tdlm. tmux renames the SESSION and opens windows; herdr renames the
# WORKSPACE and opens tabs.
function hdlm --description 'hdl in a tab per subdirectory'
    if test (count $argv) -eq 0
        echo "Usage: hdlm <ai-command> [second-ai-command]"
        return 1
    end
    if not set -q HERDR_PANE_ID
        echo "You must start herdr to use hdlm."
        return 1
    end

    set -l base_dir $PWD
    set -l first true

    herdr workspace rename $HERDR_WORKSPACE_ID (basename $base_dir) >/dev/null

    for dir in $base_dir/*/
        test -d $dir; or continue
        set -l dirpath (string trim -r -c / $dir)
        if test $first = true
            # Reuse the pane this ran in for the first project.
            herdr pane run $HERDR_PANE_ID "cd '$dirpath' && hdl $argv" >/dev/null
            set first false
        else
            set -l pane_id (herdr tab create --workspace $HERDR_WORKSPACE_ID --cwd $dirpath --no-focus \
                | jq -r '.result.root_pane.pane_id')
            herdr pane run $pane_id "hdl $argv" >/dev/null
        end
    end
end
