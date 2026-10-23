#!/usr/bin/env bash
# A sink that is both default and preferred vanishes, as an AirPods link that drops does, and the shell lives on.
{
source "$(dirname "$0")/lib.sh"

under_dev() { case $1 in "$DOTS_DEV_DIR"/*) true ;; *) false ;; esac; }
under_dev "${PIPEWIRE_RUNTIME_DIR:-}" || { echo "FAIL PIPEWIRE_RUNTIME_DIR is not the nested one"; exit 1; }

control_state() { timeout 0.5 qs ipc call control state 2>/dev/null; }
state_is() { control_state | jq -e "$@" >/dev/null 2>&1; }
shell_pid() { systemctl --user show -p MainPID --value "$DOTS_DEV_UNIT"; }
gone_id() { pw-dump 2>/dev/null | jq -e 'first(.[] | select(.info.props["node.name"]? == "dots-gone") | .id)'; }

until_ok 5000 shell_status >/dev/null
niri msg action spawn -- dots-call control toggle
until_ok 3000 state_is '.open and .section == "audio"'

# The node exists before the defaults name it, so the shell's handle on it is older than either default's.
pw-cli create-node adapter '{ factory.name = support.null-audio-sink node.name = dots-gone media.class = Audio/Sink audio.position = [ FL FR ] object.linger = true }' >/dev/null
until_ok 3000 gone_id >/dev/null
pw-metadata -n default 0 default.configured.audio.sink '{"name":"dots-gone"}' Spa:String:JSON >/dev/null
pw-metadata -n default 0 default.audio.sink '{"name":"dots-gone"}' Spa:String:JSON >/dev/null
until_ok 3000 state_is '.defaultSink == "dots-gone"'
check "Control shows the new sink as the default" state_is '.defaultSink == "dots-gone"'

pid=$(shell_pid)
pw-cli destroy "$(gone_id)" >/dev/null
sleep 1
check "the shell is the same process after the default sink vanishes" test "$(shell_pid)" = "$pid"
answers() { until_ok 2000 shell_status >/dev/null; }
check "the shell still answers" answers
check "Control shows no default sink" state_is '.defaultSink == null'

exit $((fails > 0))
}
