#!/usr/bin/env bash
# just dev: its tmux server, dconf database and Chromium policy dir all live inside its temp dir.
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
check "the dconf db file is deleted" test -n "$db_name" -a ! -e "$db" -a ! -e "$XDG_RUNTIME_DIR/dconf/$db_name"

exit $((fails > 0))
