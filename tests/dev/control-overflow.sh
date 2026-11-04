#!/usr/bin/env bash
# A Control row wider than the panel, as the NUC's HDMI card draws: when name and detail both run long, the name keeps half the row and the detail elides in the rest; neither runs past the row.
{
export DOTS_DEV_WIREPLUMBER=1
source "$(dirname "$0")/lib.sh"

under_dev() { case $1 in "$DOTS_DEV_DIR"/*) true ;; *) false ;; esac; }
under_dev "${PIPEWIRE_RUNTIME_DIR:-}" || { echo "FAIL PIPEWIRE_RUNTIME_DIR is not the nested one"; exit 1; }

players=()
cleanup() { [ ${#players[@]} -eq 0 ] || kill "${players[@]}" 2>/dev/null; }
control_state() { timeout 0.5 qs ipc call control state 2>/dev/null; }
state_is() { control_state | jq -e "$@" >/dev/null 2>&1; }
node_id() { pw-dump 2>/dev/null | jq -e --arg k "$1" --arg v "$2" 'first(.[] | select(.info.props[$k]? == $v) | .id)'; }
select_row() {
  local i n
  i=$(control_state | jq --arg t "$1" '.rows | index($t)')
  [ -n "$i" ] && [ "$i" != null ] || return 1
  for n in 1 2 3 4 5 6 7 8; do
    state_is --argjson i "$i" '.selected == $i' && return 0
    if state_is --argjson i "$i" '.selected < $i'; then wtype j; else wtype k; fi
    sleep 0.1
  done
  return 1
}
in_theme() { legacy_theme "$1" >/dev/null; until_ok 2000 eval 'shell_status | jq -e --arg t "$1" ".theme == \$t" >/dev/null'; }

long="Built-in Audio Digital Stereo (HDMI) Output + Analog Stereo Input on HDMI / DisplayPort 3 of the NUC"
until_ok 5000 shell_status >/dev/null
pw-cli create-node adapter "{ factory.name = support.null-audio-sink node.name = dots-long node.description = \"$long\" media.class = Audio/Sink audio.position = [ FL FR ] object.linger = true }" >/dev/null
until_ok 3000 node_id node.name dots-long >/dev/null
pw-play --target dots-long -P '{ application.name = "Wide Player" node.name = wide-player }' --raw --rate 48000 --channels 2 --format s16 - </dev/zero 2>/dev/null &
players+=($!)
until_ok 3000 node_id application.name "Wide Player" >/dev/null
both="A Player Whose Own Name Runs On Far Past Half Of The Row Here"
pw-play --target dots-long -P "{ application.name = \"$both\" node.name = both-player }" --raw --rate 48000 --channels 2 --format s16 - </dev/zero 2>/dev/null &
players+=($!)
until_ok 3000 node_id application.name "$both" >/dev/null

for theme in blueprint hi-fi paper artboard; do
  in_theme "$theme"
  niri msg action spawn -- dots-call control toggle
  until_ok 3000 state_is '.open and .section == "audio" and .settled'
  until_ok 3000 state_is --arg t "$long" '.rows | index($t) != null'
  until_ok 3000 state_is '.rows | index("Wide Player") != null'

  # The app row's detail is the long sink's description: it elides inside the row and the short name stays whole.
  until_ok 3000 select_row "Wide Player"
  until_ok 1000 state_is '.cursorDetail.truncated'
  check "$theme: a long detail elides ($(control_state | jq -c '.cursorDetail.truncated'))" state_is '.cursorDetail.truncated'
  check "$theme: a long detail ends inside its row ($(control_state | jq -c '[.cursorDetail.x + .cursorDetail.w, .cursorBox.x + .cursorBox.w]'))" \
    state_is '.cursorDetail.x + .cursorDetail.w <= .cursorBox.x + .cursorBox.w'
  check "$theme: the name beside a long detail stays whole ($(control_state | jq -c '[.cursorName.w, .cursorName.truncated]'))" \
    state_is '.cursorName.w > 0 and (.cursorName.truncated | not)'

  # The long sink's own row: its name takes the room its short detail leaves, and elides.
  until_ok 3000 select_row "$long"
  check "$theme: a long name elides ($(control_state | jq -c '.cursorName.truncated'))" state_is '.cursorName.truncated'
  check "$theme: a long name ends inside its row" state_is '.cursorName.x + .cursorName.w <= .cursorBox.x + .cursorBox.w'
  check "$theme: the detail beside a long name stays whole ($(control_state | jq -c '.cursorDetail.truncated'))" state_is '.cursorDetail.truncated | not'
  check "$theme: the detail beside a long name ends inside its row" state_is '.cursorDetail.x + .cursorDetail.w <= .cursorBox.x + .cursorBox.w'


  # A long name beside a long detail: side by side both elide and the name keeps half the row; Artboard's name has a line of its own.
  until_ok 3000 select_row "$both"
  check "$theme: neither runs past the row" state_is '.cursorDetail.x + .cursorDetail.w <= .cursorBox.x + .cursorBox.w and .cursorName.x + .cursorName.w <= .cursorBox.x + .cursorBox.w'
  if [ "$theme" != artboard ]; then
    check "$theme: beside each other, a long name and a long detail both elide" state_is '.cursorName.truncated and .cursorDetail.truncated'
    check "$theme: the name keeps about half the row ($(control_state | jq -c '[.cursorName.w, .cursorBox.w]'))" \
      state_is '.cursorName.w <= .cursorBox.w / 2 and .cursorName.w >= .cursorBox.w / 2 - 80'
  fi

  timeout 0.5 qs ipc call control close
  until_ok 2000 state_is '.open == false and .drawing == false'
done

in_theme paper
pw-cli destroy "$(node_id node.name dots-long)" >/dev/null
exit $((fails > 0))
}
