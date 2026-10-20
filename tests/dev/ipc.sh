#!/usr/bin/env bash
# niri's binds reach the shell over its own socket through dots-call, in a few ms against qs ipc's tens; a call the socket cannot answer falls back to qs ipc.
{
repo=$(cd "$(dirname "$0")/../.." && pwd)
# The nested shell runs a copy, so this check's edit never reaches the shell/ the live shell watches.
copy=$(mktemp -d)
cp -a "$repo/shell" "$copy/shell"
ln -s "$repo/bin" "$copy/bin"
export DOTS_DEV_SHELL=$copy/shell
source "$(dirname "$0")/lib.sh"
# A PATH with socat but no qs, so a call that fell back to qs ipc cannot pass for one the socket answered.
noqs=$(mktemp -d)
for t in bash sh socat timeout printf cat jq date; do ln -s "$(command -v "$t")" "$noqs/$t"; done
cleanup() { rm -rf "$copy" "$noqs"; }
socket_only() { env PATH="$noqs" "$repo/bin/dots-call" "$@"; }
shell_pid() { systemctl --user show -p MainPID --value "$DOTS_DEV_UNIT"; }

until_ok 5000 shell_status >/dev/null
answers() { socket_only shell status | jq -e '(.firstFrameMs | type) == "number"' >/dev/null 2>&1; }
until_ok 3000 answers
check "dots-call shell status answers over the socket, with no qs on PATH" answers

# A function no handler declares runs nothing over the socket, so qs ipc gives its own answer.
check "a call the socket cannot answer is passed to qs ipc (no qs here, so it fails)" bash -c '! env PATH='"$noqs"' '"$repo"'/bin/dots-call shell nosuchfunction >/dev/null 2>&1'
fallback=$("$repo/bin/dots-call" shell nosuchfunction 2>&1)
check "and with qs on PATH, qs ipc answers it ($fallback)" grep -qi 'not found' <<<"$fallback"

# The bind's own path: niri spawns dots-call, which reaches the launcher over the socket.
launcher_open() { socket_only launcher state | jq -e '.open' >/dev/null 2>&1; }
niri msg action spawn -- dots-call launcher toggle
until_ok 3000 launcher_open
check "niri spawning dots-call launcher toggle opens the launcher" launcher_open
socket_only launcher close
until_ok 3000 bash -c "! env PATH=$noqs $repo/bin/dots-call launcher state | jq -e .open >/dev/null"

# A call that failed fast must not pass for a fast one, so it counts as 999 ms.
ms() { local t0; t0=$(date +%s%N); socket_only shell status | jq -e . >/dev/null 2>&1 || { echo 999; return; }; echo $((($(date +%s%N) - t0) / 1000000)); }
times=()
for _ in 1 2 3 4 5 6 7 8 9; do times+=("$(ms)"); done
median=$(printf '%s\n' "${times[@]}" | sort -n | sed -n 5p)
check "a socket call takes under 15 ms, the median of nine (${times[*]})" test "$median" -lt 15

# A killed shell leaves its socket file behind, and the restarted one must still bind the path.
old=$(shell_pid)
systemctl --user kill -s KILL "$DOTS_DEV_UNIT"
restarted() { [ "$(shell_pid)" != "$old" ] && [ "$(shell_pid)" != 0 ] && answers; }
until_ok 8000 restarted
check "after a kill and restart, dots-call still answers over the socket" restarted

# A hot reload tears the old server down and starts a new one on the same path.
config=$(tr '\0' '\n' <"/proc/$(shell_pid)/environ" | sed -n 's/^QS_CONFIG_PATH=//p')
loads() { journalctl --user -u "$DOTS_DEV_UNIT" --no-pager -o cat | grep -c 'Configuration Loaded'; }
before=$(loads)
echo "// reload" >>"$config/shell.qml"
reloaded() { (($(loads) > before)); }
until_ok 5000 reloaded
sleep 0.5
until_ok 3000 answers
check "after a hot reload, dots-call still answers over the socket" answers

exit $((fails > 0))
}
