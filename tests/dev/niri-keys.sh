#!/usr/bin/env bash
# The niri binds that move windows and workspaces do their job. niri runs no binds for wtype's virtual keyboard, and uinput would reach the live session, so the check reads each bind's action out of binds.kdl and runs that text through niri msg.
{
source "$(dirname "$0")/lib.sh"

# The text between the braces of the line that binds $1, without the trailing semicolon.
bind_action() {
  grep -m1 -E "^[[:space:]]*${1//+/\\+}[[:space:]].*\{" "$DOTS_NIRI_BINDS" | sed -E 's/.*\{[[:space:]]*(.*[^;[:space:]])[;[:space:]]*\}.*/\1/'
}
# Runs a bind's action; a missing bind leaves the action empty and fails the step.
run_bind() {
  local action
  action=$(bind_action "$1")
  [ -n "$action" ] || return 1
  # shellcheck disable=SC2086
  niri msg action $action
}
foot_count() { niri msg -j windows | jq '[.[] | select(.app_id == "foot")] | length'; }
foots_open() { [ "$(foot_count)" = 2 ]; }
columns() { niri msg -j windows | jq '[.[] | select(.app_id == "foot") | .layout.pos_in_scrolling_layout[0]] | unique | length'; }
columns_are() { [ "$(columns)" = "$1" ]; }
focused_ws_idx() { niri msg -j workspaces | jq '.[] | select(.is_focused) | .idx'; }
ws_idx_is() { [ "$(focused_ws_idx)" = "$1" ]; }

until_ok 5000 shell_status >/dev/null
niri msg action spawn -- foot -c /dev/null
niri msg action spawn -- foot -c /dev/null
until_ok 8000 foots_open

# Two windows in one column, the second focused.
niri msg action focus-column-first
niri msg action consume-window-into-column
niri msg action focus-window-down
until_ok 2000 columns_are 1
check "two windows share one column" columns_are 1

run_bind Mod+Shift+Comma
until_ok 2000 columns_are 2
check "Mod+Shift+Comma pulls the window out into its own column" columns_are 2

# niri keeps the empty workspace last, so the workspace to move needs a non-empty one below it.
niri msg action move-window-to-workspace-down
niri msg action focus-workspace-up
until_ok 2000 ws_idx_is 1
check "the focused workspace starts at index 1" ws_idx_is 1
run_bind Mod+Shift+Page_Down
until_ok 2000 ws_idx_is 2
check "Mod+Shift+Page_Down moves the workspace from index 1 to 2" ws_idx_is 2
run_bind Mod+Shift+Page_Up
until_ok 2000 ws_idx_is 1
check "Mod+Shift+Page_Up moves it back to index 1" ws_idx_is 1

exit $((fails > 0))
}
