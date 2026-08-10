# Split a herdr pane and echo the id of the new pane (omarchy's _herdr_split,
# CREDITS.md). --ratio is the share the ORIGINAL pane keeps, so 0.85 down
# leaves a 15% strip underneath.
function _herdr_split --description 'Split a herdr pane, echo the new pane id'
    herdr pane split $argv[1] --direction $argv[2] --ratio $argv[3] --cwd $argv[4] --no-focus \
        | jq -r '.result.pane.pane_id'
end
