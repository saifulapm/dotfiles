#!/usr/bin/env bash
# Mod+T draws the tailnet in the island as board 8 does: a switch, this device as a tile, the machines with an ok dot when online and their age when not. Enter copies an online machine's address, s sends it picked files, the switch and t turn Tailscale off and on, an offline machine only says so, and tailscale runs nothing once the surface closes.
{
source "$(dirname "$0")/lib.sh"
source "$(dirname "$0")/pointer.bash"

ts_dir=$DOTS_DEV_DIR/tailscale
# The shell presses t on whatever tailscale its PATH finds, so the check ends before any key unless that is the fake.
unit_path=$(systemctl --user show -p Environment --value "$DOTS_DEV_UNIT" | tr ' ' '\n' | sed -n 's/^PATH=//p')
if [ "$(PATH=$unit_path command -v tailscale)" != "$repo/dev/path/tailscale" ]; then
  echo "FAIL the shell unit resolves tailscale to the fake"
  exit 1
fi

ts_state() { timeout 0.5 dots-call tailscale state 2>/dev/null; }
state_is() { ts_state | jq -e "$@" >/dev/null 2>&1; }
island() { timeout 0.5 qs ipc call island state 2>/dev/null; }
clip() { timeout 1 wl-paste -n 2>/dev/null; }
# niri runs no binds for wtype's virtual keyboard, so the check spawns the bind's command through niri.
open_ts() { niri msg action spawn -- dots-call tailscale toggle; until_ok 3000 state_is '.open and .listed and .settled and .keyboard'; }
close_ts() { wtype -k Escape; until_ok 3000 state_is '.drawing == false'; }
cursor_to() {
  local i
  for i in 1 2 3 4 5 6; do
    until_ok 300 state_is --arg n "$1" '.rows[.selected].name == $n' && return 0
    wtype j
  done
  return 1
}
fake_status() { jq -r .BackendState "$ts_dir/status.json"; }
# A line in the fake's change log wakes the surface's watcher, as tailscaled's bus does on a change.
wake() { echo '{"State":"Running"}' >>"$ts_dir/changes"; }
edit_status() { jq "$@" "$ts_dir/status.json" >"$ts_dir/status.tmp" && mv "$ts_dir/status.tmp" "$ts_dir/status.json" && wake; }
watchers() { pgrep -f -- "$repo/dev/path/tailscale debug watch-ipn" >/dev/null; }
calls() { wc -l <"$ts_dir/calls.log"; }
# The island's own fill as it reports it, in the lower case Qt writes colours in.
island_fill() { island | jq -r '.fill.color | ascii_downcase'; }

check "before Mod+T the surface is not loaded" state_is '.loaded == false'
check "and nothing watches tailscale" eval '! watchers'

open_ts
echo "     tailscale: $(ts_state | jq -c '{state, online, switchOn, rows: [.rows[] | [.name, .line, .dot]], device, heading}')"
check "Mod+T sets the island's surface to tailscale ($(island | jq -c .surface))" eval "island | jq -e '.surface == \"tailscale\"' >/dev/null"
check "Mod+T opens the list from tailscale status: 5 rows, 3 online, on" state_is '.state == "on" and .online == 3 and (.rows | length) == 5'
check "the switch is on while the tailnet is up" state_is '.switchOn and .heading == "Tailscale"'
check "the rows are online by name, then offline most recently seen first" state_is '[.rows[].name] == ["iphone", "mini", "nuc", "saifuls-mac-mini", "fedora"]'
check "online rows draw their address, offline ones offline and their age as 3 d" state_is '[.rows[].ip] == ["100.95.3.21", "100.72.40.9", "100.88.14.3", "", ""] and (.rows[4].line | test("^offline · [0-9]+ d$"))'
check "this device draws as a tile: macbook, this device · 100.101.7.12" state_is '.device == {name: "macbook", line: "this device · 100.101.7.12", ip: "100.101.7.12"}'
check "an online machine has a dot in the ok tone, an offline one a muted dot and line" state_is '(.ok | ascii_downcase) as $ok | (.muted | ascii_downcase) as $m | all(.rows[0:3][]; .dot == $ok) and all(.rows[3:][]; .dot != $ok and .ink == $m)'
check "the selected row is lighter and its Send is inverted: the island's ink as fill, its fill as text" state_is '.rows[.selected].send == {text: "Send", fill: .ink, ink: .fill} and (.rows[.selected].fill | test("^#1f")) and ([.rows[] | select(.send != null)] | length) == 1'
check "rows draw on the island's fill in the island's ink ($(island_fill))" state_is --arg f "$(island_fill)" '(.fill | ascii_downcase) == $f and .rows[0].ink == .ink and .ink != .fill'
check "the legend and key strip are gone" state_is 'has("hint") | not'
check "while open, the surface watches tailscale" watchers

cursor_to nuc
wtype -k Return
until_ok 3000 bash -c '[ "$(timeout 1 wl-paste -n 2>/dev/null)" = 100.88.14.3 ]'
check "Enter on nuc copies 100.88.14.3 ($(clip))" test "$(clip)" = 100.88.14.3
check "and closes the surface" until_ok 2000 state_is '.open == false'

# The picked files are listed before s on fedora, so a chooser that ran would lead to a file cp in the fake's log.
printf '' >"$DOTS_DEV_DIR/a.txt"
head -c 100000 /dev/zero >"$DOTS_DEV_DIR/b.txt"
printf '%s\n' "$DOTS_DEV_DIR/a.txt" "$DOTS_DEV_DIR/b.txt" >"$DOTS_DEV_DIR/picked"
printf 'before-fedora' | wl-copy
open_ts
cursor_to fedora
wtype -k Return
until_ok 2000 state_is '.offlineLine != ""'
check "Enter on fedora draws fedora is offline ($(ts_state | jq -c .offlineLine))" state_is '.offlineLine == "fedora is offline" and .open'
check "and leaves the clipboard as it was ($(clip))" test "$(clip)" = before-fedora
wtype k
until_ok 2000 state_is '.offlineLine == ""'
cursor_to fedora
wtype s
until_ok 2000 state_is '.offlineLine != ""'
sleep 1.5
check "s on fedora draws the same line ($(ts_state | jq -c .offlineLine))" state_is '.offlineLine == "fedora is offline" and .open'
check "and sends nothing: the fake logged no file cp" test ! -e "$ts_dir/cp.log"
check "and no dots-taildrop-send runs" eval '! pgrep -f "[d]ots-taildrop-send" >/dev/null'
close_ts

# a.txt is empty and b.txt 100 kB, so the fake's 48% on the second file is 48% of the whole send.
sent_48() { island | jq -e '.mode == "sending" and (.text | contains("48%"))' >/dev/null 2>&1; }
open_ts
cursor_to nuc
wtype s
check "s on nuc puts the send in the island's sending slot at 48%" until_ok 8000 sent_48
summaries() { timeout 0.5 qs ipc call notifs state 2>/dev/null | jq -e --arg s "$1" 'any(.summaries[]; . == $s)' >/dev/null; }
check "and Sent 2 files to nuc lands in the notification centre" until_ok 8000 summaries "Sent 2 files to nuc"
check "the fake logged one file cp of both to 100.88.14.3: ($(cat "$ts_dir/cp.log" 2>/dev/null))" test "$(cat "$ts_dir/cp.log" 2>/dev/null)" = "file cp $DOTS_DEV_DIR/a.txt $DOTS_DEV_DIR/b.txt 100.88.14.3:"

open_ts
click_box tailscale-switch
until_ok 3000 state_is '.state == "off"'
check "turning the switch off runs the fake's tailscale down ($(fake_status), last call: $(tail -n1 "$ts_dir/calls.log" | head -c 40))" bash -c "[ '$(fake_status)' = Stopped ] && grep -qx down '$ts_dir/calls.log'"
check "and the list reads off: Tailscale is off, no rows, the switch off ($(ts_state | jq -c '[.line, (.rows | length)]'))" state_is '.line == "Tailscale is off" and .rows == [] and .switchOn == false'
check "with the device tile still drawn" state_is '.device.name == "macbook" and .device.ip == "100.101.7.12"'
wtype t
until_ok 3000 state_is '.state == "on" and (.rows | length) == 5'
check "t turns it on again ($(fake_status)) and the rows come back" bash -c "[ '$(fake_status)' = Running ] && timeout 0.5 dots-call tailscale state | jq -e '.switchOn and (.rows | length) == 5' >/dev/null"

# Without an operator, tailscaled refuses a non-root up or down, and Tailscale says why at its foot instead of t doing nothing: the island draws Tailscale, not its notice, while Tailscale is open.
touch "$ts_dir/denied"
wtype t
says_why() { state_is '.note | startswith("Tailscale not turned off · Access denied")'; }
check "a refused t says why at Tailscale's foot ($(ts_state | jq -r .note))" until_ok 3000 says_why
check "and Tailscale stays on" state_is '.state == "on"'
rm "$ts_dir/denied"

echo NeedsLogin >"$ts_dir/state"
wake
until_ok 3000 state_is '.state == "loggedOut"'
check "logged out: one line, no rows ($(ts_state | jq -c '[.line, (.rows | length)]'))" state_is '.line == "Tailscale is logged out" and .rows == [] and .device.name == "macbook"'
rm -f "$ts_dir/state"
touch "$ts_dir/down"
wake
until_ok 3000 state_is '.state == "down"'
check "tailscaled not running: one line, no rows ($(ts_state | jq -c '[.line, (.rows | length)]'))" state_is '.line == "tailscaled is not running" and .rows == [] and .device == null'
rm -f "$ts_dir/down"
wake
until_ok 3000 state_is '.state == "on" and (.rows | length) == 5'

long=$(printf 'l%.0s' {1..200})
edit_status --arg long "$long" '.Peer["nodekey:06"] = {HostName: "x", DNSName: ($long + ".taila27604.ts.net."), Online: true, TailscaleIPs: ["100.64.0.6"]}
  | .Peer["nodekey:07"] = {HostName: "y", DNSName: "two\nlines\u202eevil.taila27604.ts.net.", Online: true, TailscaleIPs: ["100.64.0.7"]}'
until_ok 3000 state_is '(.rows | length) == 7'
echo "     forged: $(ts_state | jq -c '[.rows[] | select(.name | startswith("two") or startswith("lll")) | {name: .name[0:24], lines, elided, right, width}]')"
check "a name with a newline and U+202E draws as one line without them" state_is 'any(.rows[]; .name == "two linesevil" and .lines == 1)'
check "a 200-character name draws on one line, elided inside its row" state_is 'any(.rows[]; (.name | startswith("lll")) and .lines == 1 and .elided and .right <= .width)'
edit_status 'del(.Peer["nodekey:06"], .Peer["nodekey:07"])'
until_ok 3000 state_is '(.rows | length) == 5'

check "the surface is drawn 640 px wide ($(ts_state | jq -c .width))" state_is '.width == 640'

before=$(calls)
close_ts
sleep 1
check "1 s after Esc the fake tailscale's log gains no new line ($before lines)" test "$(calls)" = "$before"
check "within 30 s of Esc no tailscale debug watch-ipn is left" until_ok 30000 eval '! watchers'
until_ok 33000 state_is '.loaded == false'
check "30 s after close shell status no longer lists tailscale as loaded" bash -c "timeout 0.5 qs ipc call shell status | jq -e 'all(.loaded[]; . != \"tailscale\")' >/dev/null"

# Mod+Space opens the launcher, which closes Tailscale through the surfaces; a bus line then wakes nothing, and no tailscale runs.
open_ts
before=$(calls)
niri msg action spawn -- dots-call launcher toggle
until_ok 3000 state_is '.open == false'
wake
sleep 1
check "1 s after Mod+Space morphs Tailscale away the fake tailscale's log gains no new line ($before lines)" test "$(calls)" = "$before"
until_ok 3000 eval "island | jq -e '.surface == \"launcher\" and .animating == false' >/dev/null"
niri msg action spawn -- dots-call launcher toggle
until_ok 3000 eval "island | jq -e '.surface == null and .animating == false' >/dev/null"

exit $((fails > 0))
}
