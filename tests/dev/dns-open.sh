#!/usr/bin/env bash
# DNS Shield draws the cached state before the full one answers; o and O open a Kid device for a while, its badge counts down, and Kid comes back at the deadline, also when it passed while the shell was down.
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
wtype o
check "o on the iPad logs one open $ipad 30m" until_ok 3000 logged_is "open $ipad 30m" 1
check "its row's badge reads open · 30:00 left or a second or so less ($(badge_of "$ipad"))" until_ok 3000 badge_like "$ipad" '^open · (30:00|29:5[0-9]) left$'
echo "     pane: $(dns_state | jq -c '.pane | {path, badge, paused, categories: [.categories[].value], until, left}')"
check "the pane says Kid mode is paused until HH:MM" state_is '.pane.path | test("^Carried profile · Kid mode paused until [0-9]{2}:[0-9]{2}$")'
check "its categories read paused while open" state_is '.pane.paused == "paused while open" and ([.pane.categories[].value] == ["paused", "paused", "paused", "paused", "paused"])'
check "and OPEN reads Open until HH:MM with the time left" state_is '(.pane.until | test("^Open until [0-9]{2}:[0-9]{2}$")) and (.pane.left | test("^(30:00|29:[0-9]{2}) left$"))'
first=$(badge_of "$ipad")
sleep 1.5
check "the badge counts down while the card shows ($first, then $(badge_of "$ipad"))" test "$(badge_of "$ipad")" != "$first"

wtype O
check "O logs one open $ipad 2h" until_ok 3000 logged_is "open $ipad 2h" 1
check "and the badge reads open · 120:00 left or a little less ($(badge_of "$ipad"))" until_ok 3000 badge_like "$ipad" '^open · (120:00|119:5[0-9]) left$'
idle
wtype -k space
check "space ends the open: one kid $ipad on" until_ok 3000 logged_is "kid $ipad on" 1
check "and the row reads KID with its categories back" until_ok 3000 state_is --arg k "$ipad" 'any(.rows[]; .key == $k and .badge == "KID") and ([.pane.categories[].value] == ["ON", "OFF", "ON", "ON", "OFF"])'

# A 5-second open runs out with the card shown: the card reads state again at 0:00 and the collector brings Kid back.
idle
echo 5 >"$DOTS_DEV_DIR/dns-open-seconds"
wtype o
until_ok 3000 badge_like "$ipad" '^open · 00:0[0-5] left$'
reads=$(logged state)
check "a 5-second open reads KID once it runs out ($(badge_of "$ipad"))" until_ok 10000 badge_like "$ipad" '^KID$'
check "the card read state again at the deadline, with no key pressed ($reads, then $(logged state) state calls)" test "$(logged state)" -gt "$reads"
rm "$DOTS_DEV_DIR/dns-open-seconds"
close_dns

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
check "DNS Shield then draws the iPad as KID" badge_like "$ipad" '^KID$'
close_dns

exit $((fails > 0))
}
