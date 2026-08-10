# Herdr swarm: N panes in a grid, all running the same command — the herdr
# twin of tsl. tmux got its grid from `select-layout tiled`; herdr has no
# such command, so the tiling is done here, the way omarchy's hsl does it.
function hsl --description 'Herdr swarm: N tiled panes, one command'
    if test (count $argv) -lt 2
        echo "Usage: hsl <pane-count> <command>"
        return 1
    end
    if not set -q HERDR_PANE_ID
        echo "You must start herdr to use hsl."
        return 1
    end

    set -l count $argv[1]
    set -l cmd (string join ' ' $argv[2..])
    set -l current_dir $PWD

    herdr tab rename $HERDR_TAB_ID (basename $current_dir) >/dev/null

    # ceil(sqrt(count)) columns, with the rows spread across them.
    set -l cols 1
    while test (math "$cols * $cols") -lt $count
        set cols (math $cols + 1)
    end

    # Each split hands the ORIGINAL pane `ratio` of the space, so peeling the
    # rightmost column off at 1/(cols-k+1) leaves every column even — and
    # keeps the list in left-to-right order.
    set -l columns $HERDR_PANE_ID
    for k in (seq 1 (math $cols - 1))
        set -a columns (_herdr_split $columns[-1] right (math "1 / ($cols - $k + 1)") $current_dir)
    end

    # Split each column into its share of rows, evenly and top-to-bottom.
    set -l panes
    for index in (seq 1 $cols)
        set -l rows (math "floor($count / $cols)")
        # The leftmost columns absorb the remainder.
        test $index -le (math "$count % $cols"); and set rows (math $rows + 1)
        set -l last $columns[$index]
        set -a panes $last
        for j in (seq 1 (math $rows - 1))
            set last (_herdr_split $last down (math "1 / ($rows - $j + 1)") $current_dir)
            set -a panes $last
        end
    end

    for pane in $panes
        herdr pane run $pane "$cmd" >/dev/null
    end
end
