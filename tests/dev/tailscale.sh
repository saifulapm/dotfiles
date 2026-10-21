#!/usr/bin/env bash
# Mod+T lists the tailnet: Enter copies an online machine's address, s sends it picked files, t turns Tailscale off and on, an offline machine only says so, and nothing watches tailscale once it closes.
{
source "$(dirname "$0")/lib.sh"

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
status_theme() { shell_status | jq -e --arg t "$1" '.theme == $t' >/dev/null; }
in_theme() { "$repo/bin/dots" theme "$1" >/dev/null; until_ok 2000 status_theme "$1"; }
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
# Pixels of geometry $1 within 12 of the hex colour $2.
near() {
  grim -s 1 -t ppm -g "$1" - | node -e '
    const b = require("fs").readFileSync(0), hex = process.argv[1];
    const [r, g, bl] = [1, 3, 5].map((i) => parseInt(hex.slice(i, i + 2), 16));
    const head = b.toString("latin1").match(/^P6\s+(\d+)\s+(\d+)\s+(\d+)\s/), px = b.subarray(head[0].length);
    let n = 0;
    for (let i = 0; i < head[1] * head[2]; i++) if (Math.abs(px[i * 3] - r) <= 12 && Math.abs(px[i * 3 + 1] - g) <= 12 && Math.abs(px[i * 3 + 2] - bl) <= 12) n++;
    console.log(n);
  ' "$2"
}
badge_geo() { ts_state | jq -r '.badgeBox | "\(.x | floor),\(.y | floor) \(.w | ceil)x\(.h | ceil)"'; }

check "before Mod+T the surface is not loaded" state_is '.loaded == false'
check "and nothing watches tailscale" eval '! watchers'

open_ts
echo "     tailscale: $(ts_state | jq -c '{state, online, rows: [.rows[] | [.name, .ip, .status]], device, heading, badge, hint}')"
check "Mod+T opens the list from tailscale status: 5 rows, 3 online, on" state_is '.state == "on" and .online == 3 and (.rows | length) == 5'
check "the rows are online by name, then offline most recently seen first" state_is '[.rows[].name] == ["iphone", "mini", "nuc", "saifuls-mac-mini", "fedora"]'
check "online rows draw their address, offline ones none and their age in days" state_is '[.rows[].ip] == ["100.95.3.21", "100.72.40.9", "100.88.14.3", "", ""] and (.rows[4].status | test("^offline \\d+d$"))'
check "this device is drawn: macbook, 100.101.7.12, taila27604.ts.net" state_is '.device == {name: "macbook", ip: "100.101.7.12", tailnet: "taila27604.ts.net"}'
check "the key strip reads ↵ COPY IP · S SEND FILES · T TURN OFF · ESC" state_is '.hint == "↵ COPY IP · S SEND FILES · T TURN OFF · ESC"'
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
wtype t
until_ok 3000 state_is '.state == "off"'
check "t turns tailscale off ($(fake_status))" test "$(fake_status)" = Stopped
check "and draws Tailscale is off with no rows ($(ts_state | jq -c '[.line, (.rows | length)]'))" state_is '.line == "Tailscale is off" and .rows == []'
check "with the device block still drawn" state_is '.device.name == "macbook" and .device.ip == "100.101.7.12"'
check "the badge reads OFF and the strip t turn on · esc ($(ts_state | jq -c '[.badge, .hint]'))" state_is '.badge == "OFF" and (.hint | ascii_downcase) == "t turn on · esc"'
wtype t
until_ok 3000 state_is '.state == "on" and (.rows | length) == 5'
check "t again turns it on ($(fake_status)) and the rows come back" bash -c "[ '$(fake_status)' = Running ] && timeout 0.5 dots-call tailscale state | jq -e '.badge == \"ON\" and (.rows | length) == 5' >/dev/null"

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

for t in "paper|TAILSCALE|#3D6B3A|25|49" "artboard|Tailscale|#6C83FF|10|36" "blueprint|TAILSCALE // TAILNET|#7FE3F0|80|900"; do
  IFS='|' read -r name heading colour lo hi <<<"$t"
  close_ts
  in_theme "$name"
  open_ts
  check "$name: the panel is drawn 640 px wide ($(ts_state | jq -c .cardBox.w))" state_is '.cardBox.w == 640'
  check "$name: the heading reads $heading and the badge ON ($(ts_state | jq -c '[.heading, .badge]'))" state_is --arg h "$heading" '.heading == $h and (.badge | test("ON$"))'
  px=$(near "$(badge_geo)" "$colour")
  check "$name: the badge draws $colour ($px px, between $lo and $hi)" test "$px" -ge "$lo" -a "$px" -le "$hi"
done

close_ts
check "within 30 s of Esc no tailscale debug watch-ipn is left" until_ok 30000 eval '! watchers'
until_ok 33000 state_is '.loaded == false'
check "30 s after close shell status no longer lists tailscale as loaded" bash -c "timeout 0.5 qs ipc call shell status | jq -e 'all(.loaded[]; . != \"tailscale\")' >/dev/null"

exit $((fails > 0))
}
