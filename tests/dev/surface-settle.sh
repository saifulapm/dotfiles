#!/usr/bin/env bash
# At the live speed every surface settles within its theme's motion: Paper's drop in 140 ms, Artboard's spring in 400, Blueprint's plot in 260.
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
for s in launcher themes notifs cheatsheet goals control; do
  # This is the picker's first open, which loads its three specimens while it drops, so it may take 160 ms.
  paper_ms=140
  [ "$s" = themes ] && paper_ms=160
  settles "$s" paper drop "$paper_ms"
  settles "$s" artboard spring 400
  settles "$s" blueprint plot 260
done

# The recorder's picker opens and closes on its one toggle.
picker_settles() {
  local theme=$1 kind=$2 ms=$3
  "$repo/bin/dots" theme "$theme" >/dev/null
  until_ok 2000 status_theme "$theme"
  niri msg action spawn -- qs ipc call record toggle >/dev/null
  until_ok 3000 surface_is record .settled
  check "$theme: the recorder's picker settles as a $kind within $ms ms ($(timeout 0.5 qs ipc call record state | jq -c '[.motion, .settleMs]'))" \
    surface_is record ".picking and .motion == \"$kind\" and .settleMs > 0 and .settleMs <= $ms"
  niri msg action spawn -- qs ipc call record toggle >/dev/null
  until_ok 2000 surface_is record '.drawing == false'
}
picker_settles paper drop 140
picker_settles artboard spring 400
picker_settles blueprint plot 260

# pkexec always reaches the live polkitd, so a fake authority on the nested bus asks the nested shell's agent instead.
fake() { busctl --address="$DBUS_SESSION_BUS_ADDRESS" call org.freedesktop.PolicyKit1 /org/freedesktop/PolicyKit1/Authority org.dots.FakePolkit "$@"; }
DBUS_SYSTEM_BUS_ADDRESS=$DBUS_SESSION_BUS_ADDRESS "$repo/bin/dev-fake-polkit" &
fake_pid=$!
cleanup() { kill "$fake_pid" 2>/dev/null; }
until_ok 3000 fake Registered >/dev/null 2>&1
# The agent registers as the shell starts, so the shell restarts once the authority is up.
systemctl --user restart "$DOTS_DEV_UNIT"
until_ok 5000 surface_is polkit .registered

# A request opens the polkit prompt and Esc cancels it.
prompt_settles() {
  local theme=$1 kind=$2 ms=$3
  "$repo/bin/dots" theme "$theme" >/dev/null
  until_ok 2000 status_theme "$theme"
  fake Begin s "settle-$theme" >/dev/null
  until_ok 3000 surface_is polkit .settled
  check "$theme: the polkit prompt settles as a $kind within $ms ms ($(timeout 0.5 qs ipc call polkit state | jq -c '[.motion, .settleMs]'))" \
    surface_is polkit ".open and .motion == \"$kind\" and .settleMs > 0 and .settleMs <= $ms"
  wtype -k Escape
  until_ok 2000 surface_is polkit '.drawing == false'
}
prompt_settles paper drop 140
prompt_settles artboard spring 400
prompt_settles blueprint plot 260

"$repo/bin/dots" theme paper >/dev/null
exit $((fails > 0))
}
