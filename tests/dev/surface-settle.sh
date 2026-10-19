#!/usr/bin/env bash
# At the live speed every surface settles within its theme's motion: Paper's drop in 140 ms, Artboard's spring in 400.
{
source "$(dirname "$0")/lib.sh"
unset TMUX

status_theme() { shell_status | jq -e --arg t "$1" '.theme == $t' >/dev/null; }
surface_is() { timeout 0.5 qs ipc call "$1" state 2>/dev/null | jq -e "$2" >/dev/null; }

# Opens surface $1 in theme $2 and checks it settles as motion $3 within $4 ms, then closes it.
settles() {
  local s=$1 theme=$2 kind=$3 ms=$4
  "$repo/bin/dots" theme "$theme" >/dev/null
  until_ok 2000 status_theme "$theme"
  niri msg action spawn -- qs ipc call "$s" open >/dev/null
  until_ok 3000 surface_is "$s" .settled
  check "$theme: the $s settles as a $kind within $ms ms ($(timeout 0.5 qs ipc call "$s" state | jq -c '[.motion, .settleMs]'))" \
    surface_is "$s" ".motion == \"$kind\" and .settleMs > 0 and .settleMs <= $ms"
  timeout 0.5 qs ipc call "$s" close >/dev/null
  until_ok 2000 surface_is "$s" '.drawing == false'
}

until_ok 5000 shell_status >/dev/null
for s in launcher; do
  settles "$s" paper drop 140
  settles "$s" artboard spring 400
done

"$repo/bin/dots" theme paper >/dev/null
exit $((fails > 0))
}
