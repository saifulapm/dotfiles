#!/usr/bin/env bash
# just dev: its tmux server, dconf database, Chromium policy dir, hub file, PipeWire and rclone config all live inside its temp dir.
{
source "$(dirname "$0")/lib.sh"

dev=$DOTS_DEV_DIR
tmux_dir=${TMUX_TMPDIR:-}
profile=${DCONF_PROFILE:-}
policy=${DOTS_CHROMIUM_POLICY_DIR:-}
db_name=$(sed -n 's/^user-db://p' "$profile" 2>/dev/null)

under_dev() { case $1 in "$dev"/*) true ;; *) false ;; esac; }
check "TMUX_TMPDIR is inside the temp dir" under_dev "$tmux_dir"
check "DCONF_PROFILE is inside the temp dir" under_dev "$profile"
check "DOTS_CHROMIUM_POLICY_DIR is inside the temp dir" under_dev "$policy"

pid=$(systemctl --user show -p MainPID --value "$DOTS_DEV_UNIT")
unit_has() { grep -qzxF "$1=$2" "/proc/$pid/environ"; }
check "the shell unit carries TMUX_TMPDIR" unit_has TMUX_TMPDIR "$tmux_dir"
check "the shell unit carries DCONF_PROFILE" unit_has DCONF_PROFILE "$profile"
check "the shell unit carries DOTS_CHROMIUM_POLICY_DIR" unit_has DOTS_CHROMIUM_POLICY_DIR "$policy"

check "DOTS_HUB_QUESTIONS is inside the temp dir" under_dev "${DOTS_HUB_QUESTIONS:-}"
check "the shell unit carries DOTS_HUB_QUESTIONS" unit_has DOTS_HUB_QUESTIONS "${DOTS_HUB_QUESTIONS:-}"
check "the shell unit's system bus is the nested session bus" unit_has DBUS_SYSTEM_BUS_ADDRESS "$DBUS_SESSION_BUS_ADDRESS"
check "the shell unit carries the PATH bin/dots-dev set" unit_has PATH "$PATH"
check "PIPEWIRE_RUNTIME_DIR is inside the temp dir" under_dev "${PIPEWIRE_RUNTIME_DIR:-}"
check "the shell unit carries PIPEWIRE_RUNTIME_DIR" unit_has PIPEWIRE_RUNTIME_DIR "${PIPEWIRE_RUNTIME_DIR:-}"
check "RCLONE_CONFIG is inside the temp dir" under_dev "${RCLONE_CONFIG:-}"
check "the shell unit carries RCLONE_CONFIG" unit_has RCLONE_CONFIG "${RCLONE_CONFIG:-}"
check "DOTS_AGE_IDENTITY is inside the temp dir" under_dev "${DOTS_AGE_IDENTITY:-}"
check "the shell unit carries DOTS_AGE_IDENTITY" unit_has DOTS_AGE_IDENTITY "${DOTS_AGE_IDENTITY:-}"
# A check that runs dots sync merges the stores under XDG_DATA_HOME, so the env it sources must name the temp one.
check "XDG_DATA_HOME is inside the temp dir" under_dev "${XDG_DATA_HOME:-}"

live_volume() { env -u PIPEWIRE_RUNTIME_DIR wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null; }
live_vol_before=$(live_volume)
# Without its own PipeWire the set below would change the live volume, so it runs only inside.
under_dev "${PIPEWIRE_RUNTIME_DIR:-}" && wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.3 2>/dev/null
check "the nested default sink takes a volume of 0.30" test "$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null)" = "Volume: 0.30"
check "the live volume is still ${live_vol_before#Volume: }" test "$(live_volume)" = "$live_vol_before"

schema=org.gnome.desktop.interface key=color-scheme
live_get() { env -u DCONF_PROFILE DBUS_SESSION_BUS_ADDRESS="$live_bus" gsettings get $schema $key; }
live_set() { env -u DCONF_PROFILE DBUS_SESSION_BUS_ADDRESS="$live_bus" gsettings set $schema $key "$1"; }
live_before=$(live_get)
case $live_before in *prefer-dark*) flip=prefer-light ;; *) flip=prefer-dark ;; esac
gsettings set $schema $key "$flip" 2>/dev/null
inside=$(gsettings get $schema $key 2>/dev/null)
live_after=$(live_get)
# A leaked write must not outlive the failing test.
[ "$live_after" = "$live_before" ] || live_set "${live_before//\'/}"
check "gsettings inside reads back $flip" test "$inside" = "'$flip'"
check "the live color-scheme is still $live_before" test "$live_after" = "$live_before"

unset TMUX
tmux new-session -d -s dots-iso 'sleep 300' 2>/dev/null
sock=$(tmux display-message -p '#{socket_path}' 2>/dev/null)
check "the nested tmux socket is inside the temp dir" under_dev "$sock"
live_tmux_lists() { env -u TMUX_TMPDIR tmux ls 2>/dev/null | grep -q '^dots-iso:'; }
check "the live tmux does not list dots-iso" eval '! live_tmux_lists'

dev_stop
check "the temp dir is deleted" test ! -e "$dev"
tmux_left() { pgrep -af '[t]mux' | grep -qF "$dev"; }
check "no tmux server still uses the old temp dir" eval '! tmux_left'
db=${XDG_CONFIG_HOME:-$HOME/.config}/dconf/$db_name
pw_left() { for p in $(pgrep -x pipewire); do grep -qzF "PIPEWIRE_RUNTIME_DIR=$dev/" "/proc/$p/environ" 2>/dev/null && return 0; done; return 1; }
check "no pipewire still uses the old temp dir" eval '! pw_left'
check "the dconf db file is deleted" test -n "$db_name" -a ! -e "$db" -a ! -e "$XDG_RUNTIME_DIR/dconf/$db_name"
# qs keeps a dead instance's run dir, and every qs ipc call walks them all, so hundreds of them slow each call by 70 ms or more.
dead_left() { qs list --show-dead -j 2>/dev/null | jq -e 'length > 0' >/dev/null; }
check "no dead qs instance of this shell is left behind" eval '! dead_left'

exit $((fails > 0))
}
