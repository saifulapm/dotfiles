# Sourced by tests/dev/*.sh: runs bin/dots-dev in the background and sources the env it prints.
set -uo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
live_bus=${DBUS_SESSION_BUS_ADDRESS:-}
fails=0

check() {
  local name=$1
  shift
  if "$@"; then echo "ok   $name"; else echo "FAIL $name"; fails=$((fails + 1)); fi
}

now_ms() { echo $(($(date +%s%N) / 1000000)); }

# A stale instance socket after a kill can make a bare call hang, so every call is bounded.
shell_status() { timeout 0.5 qs ipc call shell status 2>/dev/null; }

# Polls `until_ok <ms> <cmd...>` every 50 ms until the command succeeds or the time runs out.
until_ok() {
  local deadline=$(($(now_ms) + $1))
  shift
  until "$@"; do
    (($(now_ms) < deadline)) || return 1
    sleep 0.05
  done
}

# Mean colour of a binary PPM on stdin, as "r g b".
mean_rgb() {
  node -e '
    const b = require("fs").readFileSync(0);
    const head = b.toString("latin1").match(/^P6\s+(\d+)\s+(\d+)\s+(\d+)\s/);
    const px = b.subarray(head[0].length);
    const n = head[1] * head[2], sum = [0, 0, 0];
    for (let i = 0; i < n * 3; i++) sum[i % 3] += px[i];
    console.log(sum.map((s) => Math.round(s / n)).join(" "));
  '
}

# Two nested sessions at once stretch every timing, so each check waits for the one before it to finish.
exec 9>"${XDG_RUNTIME_DIR:-/tmp}/dots-dev-check.lock"
flock -w 900 9 || { echo "FAIL another nested check held the lock for 15 min"; exit 1; }

dev_out=$(mktemp)
dev_log=$(mktemp)
# fd 9 is closed for dots-dev, so an app the nested niri spawns never holds the lock after the check ends.
"$repo/bin/dots-dev" >"$dev_out" 2>"$dev_log" 9>&- &
dev_pid=$!

dev_stop() {
  kill -TERM "$dev_pid" 2>/dev/null
  wait "$dev_pid" 2>/dev/null
  return 0
}
# A test that needs its own cleanup redefines this; the EXIT trap stays lib.sh's.
cleanup() { :; }
# A QML error can break what a surface draws while its state IPC still reads right, so every check reads the journal.
qml_errors() {
  journalctl --user -u "$DOTS_DEV_UNIT" --no-pager -o cat 2>/dev/null |
    grep -E 'TypeError|ReferenceError|SyntaxError|Failed to load configuration|is not a type|Cannot assign|Cannot read propert|unavailable|Invalid property assignment'
}
dev_exit() {
  local rc=$? errs=
  [ -n "${DOTS_DEV_UNIT:-}" ] && errs=$(qml_errors)
  if [ -n "$errs" ]; then
    echo "FAIL the shell's journal has no QML errors"
    head -5 <<<"$errs"
    rc=1
  fi
  cleanup
  dev_stop
  rm -f "$dev_out" "$dev_log"
  exit "$rc"
}
trap dev_exit EXIT

dev_settled() { grep -q DOTS_DEV_UNIT "$dev_out" || ! kill -0 "$dev_pid" 2>/dev/null; }
until_ok 15000 dev_settled
if ! grep -q DOTS_DEV_UNIT "$dev_out"; then
  echo "FAIL dots-dev never printed its env"
  cat "$dev_log"
  exit 1
fi
# shellcheck disable=SC1090
source "$dev_out"
# Every qs ipc call below must reach the worktree shell, never the live one.
: "${QS_CONFIG_PATH:?}" "${DOTS_DEV_DIR:?}" "${DOTS_DEV_UNIT:?}"

# A nested niri whose window the live session hides (a lock screen, an output off) draws about once a second, which turns every timing below into noise.
until_ok 5000 shell_status >/dev/null
grim_ms() { local t0; t0=$(now_ms); grim -s 0.1 -t ppm - >/dev/null 2>&1; echo $(($(now_ms) - t0)); }
grim_ms >/dev/null
if (($(grim_ms) > 500 && $(grim_ms) > 500)); then
  echo "FAIL the nested output draws about once a second: is the live session locked, or its output off?"
  exit 2
fi
