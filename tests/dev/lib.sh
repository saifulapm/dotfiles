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

dev_out=$(mktemp)
dev_log=$(mktemp)
"$repo/bin/dots-dev" >"$dev_out" 2>"$dev_log" &
dev_pid=$!

dev_stop() {
  kill -TERM "$dev_pid" 2>/dev/null
  wait "$dev_pid" 2>/dev/null
  return 0
}
trap 'dev_stop; rm -f "$dev_out" "$dev_log"' EXIT

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
