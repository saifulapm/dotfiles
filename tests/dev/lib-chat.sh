# Sourced by the chat checks before lib.sh: starts bin/dev-fake-pxy and puts bin/dev-fake-mem first on PATH as mem, so the chat reaches neither pxy nor the real mem.
chat_fake=$(mktemp -d)
"$(dirname "${BASH_SOURCE[0]}")/../../bin/dev-fake-pxy" "$chat_fake" >/dev/null 2>&1 9>&- &
pxy_pid=$!
for _ in $(seq 100); do
  [ -s "$chat_fake/port" ] && break
  sleep 0.05
done
pxy_port=$(cat "$chat_fake/port")
export DOTS_CHAT_URL="http://127.0.0.1:$pxy_port/v1/chat/completions"
ln -s "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/bin/dev-fake-mem" "$chat_fake/mem"
PATH=$chat_fake:$PATH
# What the chat sent pxy, one request body a line, and each argv the fake mem ran.
requests=$chat_fake/requests.jsonl
mem_log=$chat_fake/mem.log
# The fake pxy stops, so the chat meets a refused connection, and starts again on the same port.
pxy_stop() {
  kill -TERM "$pxy_pid" 2>/dev/null
  until_ok 3000 pxy_gone
}
pxy_gone() { ! kill -0 "$pxy_pid" 2>/dev/null; }
pxy_start() {
  rm -f "$chat_fake/port"
  "$(dirname "${BASH_SOURCE[0]}")/../../bin/dev-fake-pxy" "$chat_fake" "$pxy_port" >/dev/null 2>&1 9>&- &
  pxy_pid=$!
  until_ok 3000 test -s "$chat_fake/port"
}
chat_cleanup() {
  kill -TERM "$pxy_pid" 2>/dev/null
  rm -rf "$chat_fake"
}
# lib.sh may stop before it sets its own EXIT trap (an empty WAYLAND_DISPLAY, a locked session, a busy machine), so this one cleans up until then, and lib.sh's trap runs cleanup after.
trap chat_cleanup EXIT
cleanup() { chat_cleanup; }

chat() { timeout 0.5 qs ipc call chat state 2>/dev/null; }
# Whether the requests the fake pxy logged, read as one array, pass a jq test.
sent() { jq -se "$1" "$requests" >/dev/null 2>&1; }
chat_is() { chat | jq -e "$@" >/dev/null 2>&1; }
island() { timeout 0.5 qs ipc call island state 2>/dev/null; }
island_is() { island | jq -e "$@" >/dev/null 2>&1; }
# What Mod+Shift+Space spawns (binds.test.mjs pins the key; wtype's keys never reach the nested niri's binds), then wait until the chat holds the keyboard and the island has come to rest on it, so the next key reaches the field.
open_chat() {
  niri msg action spawn -- dots-call chat toggle
  until_ok 3000 chat_is '.open and .keyboard and .settled'
}
# Types a message and sends it with Enter.
say() {
  wtype -- "$1"
  wtype -k Return
}
