#!/usr/bin/env bash
# The island's Bluetooth connect state: a paired device connecting reads <name> connected · <battery>% for 2 s, never into Mod+A, never under Do Not Disturb, and never for a device already connected.
{
source "$(dirname "$0")/lib.sh"

island() { timeout 0.5 qs ipc call island state 2>/dev/null; }
island_text() { island | jq -r .text; }
reads() { [ "$(island_text)" = "$1" ]; }
mode_is() { island | jq -e --arg m "$1" '.mode == $m' >/dev/null 2>&1; }
not_mode() { ! mode_is "$1"; }
# The connect state never shows over $1 ms.
never_connect() {
  local end=$(($(now_ms) + $1))
  while (($(now_ms) < end)); do
    mode_is btConnect && return 1
    sleep 0.05
  done
}
# No battery part shows over $1 ms.
never_pct() {
  local end=$(($(now_ms) + $1))
  while (($(now_ms) < end)); do
    island_text | grep -q '%' && return 1
    sleep 0.05
  done
}
history_count() { timeout 0.5 qs ipc call notifs state 2>/dev/null | jq .count; }
dnd_is() { timeout 0.5 qs ipc call notifs state 2>/dev/null | jq -e ".dnd == $1" >/dev/null; }

# Quickshell's BlueZ client talks to the system bus, which in the nested session is the nested session bus.
bus() { busctl --address="$DBUS_SESSION_BUS_ADDRESS" "$@"; }
headphones=/org/bluez/hci0/dev_00_00_00_00_00_02
speaker=/org/bluez/hci0/dev_00_00_00_00_00_03
connect() { bus call org.bluez "$1" org.bluez.Device1 Connect; }
disconnect() { bus call org.bluez "$1" org.bluez.Device1 Disconnect; }
# -- keeps a battery of -1 from reading as an option.
battery() { bus call -- org.bluez /org/bluez org.dots.FakeBluez SetBattery oi "$1" "$2"; }

DBUS_SYSTEM_BUS_ADDRESS=$DBUS_SESSION_BUS_ADDRESS "$repo/bin/dev-fake-bluez" &
fake_pid=$!
cleanup() {
  timeout 0.5 qs ipc call notifs dnd false >/dev/null 2>&1
  disconnect "$headphones" 2>/dev/null
  kill "$fake_pid" 2>/dev/null
}
fake_up() { bus status org.bluez >/dev/null 2>&1; }
until_ok 5000 fake_up
# The shell restarts so Quickshell finds BlueZ as it starts, as it would at login.
systemctl --user restart "$DOTS_DEV_UNIT"
until_ok 10000 shell_status >/dev/null
at_rest() { shell_status | jq -e '.timers == 1' >/dev/null 2>&1 && mode_is rest; }
until_ok 6000 at_rest
check "the shell starting with the fake's devices off shows no connect state" never_connect 1000

before=$(history_count)
connect "$headphones"
until_ok 2000 mode_is btConnect
check "Test Headphones connecting shows its connect state ($(island_text))" mode_is btConnect
# The fake reports its 80% a second after the connect, as BlueZ does once the HFP link is up; it arrived after the last poll that missed it and by the one that read it.
before_pct=$(now_ms)
until reads "Test Headphones connected · 80%" || (($(now_ms) > before_pct + 3000)); do
  before_pct=$(now_ms)
  sleep 0.05
done
read_pct=$(now_ms)
check "and its battery: Test Headphones connected · 80% ($(island_text))" reads "Test Headphones connected · 80%"
until_ok 4000 not_mode btConnect
# The end comes from the shell's own mode clock, so the poll's latency does not count.
gone=$(island | jq .since)
check "it is gone 2 to 2.5 s later ($((gone - read_pct)) to $((gone - before_pct)) ms)" test $((gone - before_pct)) -ge 2000 -a $((gone - read_pct)) -le 2500
check "Mod+A gained no entry ($before, then $(history_count))" test "$(history_count)" = "$before"
check "shell status reads 1 timer once it has gone" eval 'shell_status | jq -e ".timers == 1" >/dev/null'
disconnect "$headphones"

battery "$headphones" -1
connect "$headphones"
until_ok 2000 mode_is btConnect
check "with no battery it reads Test Headphones connected ($(island_text))" reads "Test Headphones connected"
check "and no battery part comes while it shows" never_pct 1500
until_ok 3000 not_mode btConnect
disconnect "$headphones"
battery "$headphones" 80

timeout 0.5 qs ipc call notifs dnd true >/dev/null
until_ok 2000 dnd_is true
connect "$headphones"
check "with Do Not Disturb on nothing shows" never_connect 2500
disconnect "$headphones"
timeout 0.5 qs ipc call notifs dnd false >/dev/null
until_ok 2000 dnd_is false

# Test Speaker is not paired, so its connecting is no paired device connecting.
connect "$speaker"
check "an unpaired device connecting shows nothing" never_connect 2500
disconnect "$speaker"

# Connected when the shell starts, as headphones left on across a restart are.
connect "$headphones"
until_ok 2000 mode_is btConnect
until_ok 4000 not_mode btConnect
systemctl --user restart "$DOTS_DEV_UNIT"
until_ok 10000 shell_status >/dev/null
check "a device already connected when the shell starts shows nothing" never_connect 3000
connected_is() { [ "$(bus get-property org.bluez "$headphones" org.bluez.Device1 Connected 2>/dev/null)" = "b true" ]; }
check "and it is still connected" connected_is
exit $((fails > 0))
}
