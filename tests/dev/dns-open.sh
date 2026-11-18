#!/usr/bin/env bash
# DNS Shield draws the cached state before the full one answers; o and O open a Kid device for 30 min or 2 h, its chip and tile count down, Kid comes back at the deadline, also when it passed while the shell was down, and nothing reads state after Esc.
{
source "$(dirname "$0")/lib.sh"

# The shell runs whatever DOTS_DNS names, so the check ends before any open unless that is the fake.
unit_env=$(systemctl --user show -p Environment --value "$DOTS_DEV_UNIT" | tr ' ' '\n')
if ! grep -qxF "DOTS_DNS=$repo/bin/dev-fake-dns" <<<"$unit_env"; then
  echo "FAIL the shell unit's DOTS_DNS is the fake"
  exit 1
fi

log=$DOTS_DEV_DIR/dns.log
file=$DOTS_DEV_DIR/dns-state.json
dns_state() { timeout 0.5 dots-call dns state 2>/dev/null; }
state_is() { dns_state | jq -e "$@" >/dev/null 2>&1; }
# The fake logs every call, state reads included, so a write is counted by its exact line.
logged() { if [ -e "$log" ]; then grep -cxF -- "$1" "$log"; else echo 0; fi; }
logged_is() { [ "$(logged "$1")" = "$2" ]; }
open_dns() { niri msg action spawn -- dots-call dns toggle; until_ok 3000 state_is '.open and .settled and .keyboard'; }
close_dns() { wtype -k Escape; until_ok 3000 state_is '.drawing == false'; }
idle() { until_ok "${1:-3000}" state_is '.busy == false and (.rows | length) > 0'; }
badge_of() { dns_state | jq -r --arg k "$1" '.rows[] | select(.key == $k) | .badge'; }
badge_like() { state_is --arg k "$1" --arg re "$2" 'any(.rows[]; .key == $k and (.badge | test($re)))'; }
ipad=carried:dev00ipad

# The full state takes 2 s here; the cached one answers at once, so the rows draw while the full read runs.
touch "$DOTS_DEV_DIR/dns-slow-state"
niri msg action spawn -- dots-call dns toggle
check "a cold open draws the 8 cached rows while the full state still runs" until_ok 1500 state_is '(.rows | length) == 8 and .busy'
until_ok 3000 state_is '.settled and .keyboard'
idle 5000
# The shell's start ran reconcile before the open, so only the reads are compared.
read_calls() { grep -vx reconcile "$log" | paste -sd'|'; }
check "the fake ran state --cached, then state ($(read_calls))" test "$(read_calls)" = "state --cached|state"
rm "$DOTS_DEV_DIR/dns-slow-state"
close_dns
open_dns
idle

wtype j
until_ok 1000 state_is --arg k "$ipad" '.cursor == $k'
check "the iPad's tile reads Open for a while with 30 min and 2 h ($(dns_state | jq -c '.pane | [.open, .openButtons]'))" state_is '.pane.open == "Open for a while" and .pane.openButtons == ["30 min", "2 h"]'
wtype o
check "o (30 min) on the iPad logs one open $ipad 30m" until_ok 3000 logged_is "open $ipad 30m" 1
check "its row's chip reads 30:00 or a second or so less ($(badge_of "$ipad"))" until_ok 3000 badge_like "$ipad" '^(30:00|29:5[0-9])$'
echo "     pane: $(dns_state | jq -c '.pane | {kid, categories: [.categories[].value], open, left}')"
check "the tile's Kid mode switch is off" state_is '.pane.kid == false'
check "its categories read paused, their switches off" state_is '[.pane.categories[].value] == ["paused", "paused", "paused", "paused", "paused"] and all(.pane.categories[]; .on == false)'
check "and the tile reads Open until HH:MM with the time left" state_is '(.pane.open | test("^Open until [0-9]{2}:[0-9]{2}$")) and (.pane.left | test("^(30:00|29:[0-9]{2}) left$"))'
first=$(badge_of "$ipad")
sleep 1.5
check "the chip counts down while DNS Shield shows ($first, then $(badge_of "$ipad"))" test "$(badge_of "$ipad")" != "$first"

wtype O
check "O (2 h) logs one open $ipad 2h" until_ok 3000 logged_is "open $ipad 2h" 1
check "and the chip reads 120:00 or a little less ($(badge_of "$ipad"))" until_ok 3000 badge_like "$ipad" '^(120:00|119:5[0-9])$'
check "and the tile reads 120 min left ($(dns_state | jq -c .pane.left))" until_ok 1000 state_is '.pane.left | test("^(120:00|119:5[0-9]) left$")'
idle
wtype -k space
check "space ends the open: one kid $ipad on" until_ok 3000 logged_is "kid $ipad on" 1
check "and the row reads Kid with its categories back" until_ok 3000 state_is --arg k "$ipad" 'any(.rows[]; .key == $k and .badge == "Kid") and ([.pane.categories[].value] == ["blocked", "allowed", "blocked", "blocked", "allowed"])'

# A 5-second open runs out with DNS Shield shown: it reads state again at 0:00 and the collector brings Kid back.
idle
echo 5 >"$DOTS_DEV_DIR/dns-open-seconds"
wtype o
until_ok 3000 badge_like "$ipad" '^00:0[0-5]$'
reads=$(logged state)
check "a 5-second open reads Kid once it runs out ($(badge_of "$ipad"))" until_ok 10000 badge_like "$ipad" '^Kid$'
check "it read state again at the deadline, with no key pressed ($reads, then $(logged state) state calls)" test "$(logged state)" -gt "$reads"

# A 2-second open whose deadline falls after Esc: nothing reads state once DNS Shield closed, though the island still draws it through its close.
idle
echo 2 >"$DOTS_DEV_DIR/dns-open-seconds"
wtype o
until_ok 3000 badge_like "$ipad" '^00:0[12]$'
idle
wtype -k Escape
lines=$(wc -l <"$log")
sleep 2.5
check "in the 2.5 s after Esc, across the open's deadline, the fake's log gains no line ($lines, then $(wc -l <"$log"))" test "$(wc -l <"$log")" = "$lines"
until_ok 3000 state_is '.drawing == false'
rm "$DOTS_DEV_DIR/dns-open-seconds"

# An open whose deadline passed while the shell was down ends at the next start, before DNS Shield opens. The shell is frozen first, so it cannot read the file before its restart.
until_ok 33000 state_is '.loaded == false'
pid=$(systemctl --user show -p MainPID --value "$DOTS_DEV_UNIT")
kill -STOP "$pid"
jq --argjson past $((EPOCHSECONDS - 60)) '(.devices[] | select(.key == "carried:dev00ipad")) |= (.kid = false | .open_until = $past)' "$file" >"$file.tmp"
mv "$file.tmp" "$file"
: >"$log"
started=$(now_ms)
systemctl --user restart "$DOTS_DEV_UNIT"
reconciled() { grep -qx reconcile "$log"; }
check "the restarted shell runs one reconcile within 60 s of start" until_ok 60000 reconciled
echo "     reconcile after $(($(now_ms) - started)) ms; log: $(paste -sd'|' "$log")"
check "it ran nothing else: no state read, so DNS Shield did not load ($(paste -sd'|' "$log"))" test "$(paste -sd'|' "$log")" = reconcile
ipad_kid_on_disk() { jq -e '.devices[] | select(.key == "carried:dev00ipad") | .kid == true and .open_until == null' "$file" >/dev/null; }
check "and the state file has the iPad back in Kid mode" ipad_kid_on_disk
until_ok 20000 state_is '.loaded == false'
open_dns
idle
check "DNS Shield then draws the iPad with a Kid chip" badge_like "$ipad" '^Kid$'
close_dns

exit $((fails > 0))
}
