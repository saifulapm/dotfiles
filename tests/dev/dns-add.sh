#!/usr/bin/env bash
# n in DNS Shield lists the router's new leases in the card and adds one in Kid mode under a typed name; while the router is unreachable its rows dim, take no write, and the group says since when.
{
source "$(dirname "$0")/lib.sh"

# The shell runs whatever DOTS_DNS names, so the check ends before any open unless that is the fake.
unit_env=$(systemctl --user show -p Environment --value "$DOTS_DEV_UNIT" | tr ' ' '\n')
if ! grep -qxF "DOTS_DNS=$repo/bin/dev-fake-dns" <<<"$unit_env"; then
  echo "FAIL the shell unit's DOTS_DNS is the fake"
  exit 1
fi

log=$DOTS_DEV_DIR/dns.log
dns_state() { timeout 0.5 dots-call dns state 2>/dev/null; }
state_is() { dns_state | jq -e "$@" >/dev/null 2>&1; }
logged() { if [ -e "$log" ]; then grep -cxF -- "$1" "$log"; else echo 0; fi; }
logged_is() { [ "$(logged "$1")" = "$2" ]; }
calls() { if [ -e "$log" ]; then wc -l <"$log"; else echo 0; fi; }
status_theme() { shell_status | jq -e --arg t "$1" '.theme == $t and .transition == ""' >/dev/null; }
in_theme() { "$repo/bin/dots" theme "$1" >/dev/null; until_ok 4000 status_theme "$1"; }
open_dns() { niri msg action spawn -- dots-call dns toggle; until_ok 3000 state_is '.open and .settled and .keyboard'; }
close_dns() { wtype -k Escape; until_ok 3000 state_is '.drawing == false'; }
idle() { until_ok "${1:-3000}" state_is '.busy == false and (.rows | length) > 0'; }
cursor_to() { local i; for i in $(seq 1 12); do state_is --arg k "$1" '.cursor == $k' && return 0; wtype j; sleep 0.1; done; state_is --arg k "$1" '.cursor == $k'; }
adding() { until_ok 3000 state_is '.add != null and .busy == false'; }
galaxy=02:00:00:00:00:41

open_dns
idle
wtype n
adding
echo "     add: $(dns_state | jq -c '{heading, add}')"
check "n heads the card DNS SHIELD › ADD DEVICE in Paper" state_is '.heading == "DNS SHIELD › ADD DEVICE"'
check "and lists the 3 leases with their addresses under ON THE NETWORK NOW · 3" state_is '.add.head == "ON THE NETWORK NOW · 3" and ([.add.leases[] | [.name, .ip]] == [["Galaxy-A54", "192.168.0.143"], ["android-7f2c", "192.168.0.151"], ["Chromecast", "192.168.0.160"]])'
check "the cursor lease's hostname and address show at the right, and the name field starts from it" state_is --arg m "$galaxy" '.add.cursor == $m and .add.host == "Galaxy-A54" and .add.address == "192.168.0.143" and .add.name == "Galaxy-A54"'
wtype j
check "j moves to android-7f2c and the field follows" until_ok 1000 state_is '.add.cursor == "02:00:00:00:00:42" and .add.name == "android-7f2c"'
wtype k
until_ok 1000 state_is --arg m "$galaxy" '.add.cursor == $m'
wtype -k Tab
check "tab gives the name field the keyboard" until_ok 1000 state_is '.add.naming'
wtype "Sister's phone"
check "typing replaces the name ($(dns_state | jq -c .add.name))" until_ok 1000 state_is ".add.name == \"Sister's phone\""
wtype -k Return
check "Enter logs one add $galaxy Sister's phone" until_ok 3000 logged_is "add $galaxy Sister's phone" 1
check "and returns to the list with the cursor on her row" until_ok 3000 state_is --arg k "router:$galaxy" '.add == null and .cursor == $k'
check "her row reads Sister's phone, KID ($(dns_state | jq -c --arg k "router:$galaxy" '.rows[] | select(.key == $k)'))" state_is --arg k "router:$galaxy" 'any(.rows[]; .key == $k and .name == "Sister'"'"'s phone" and .badge == "KID") and .router == 6'
idle
wtype n
adding
check "her lease is gone from the list" state_is '[.add.leases[].name] == ["android-7f2c", "Chromecast"]'
wtype -k Escape
check "Esc goes back to the list, the card still open" until_ok 1000 state_is '.add == null and .open'
close_dns

# Hostnames come from whatever a device sends the router: a newline, a bidi override, an escape sequence, none at all and 200 characters.
jq -n --arg long "$(printf 'W%.0s' $(seq 1 200))" '[
  {mac: "02:00:00:00:00:51", ip: "192.168.0.151", hostname: "two\nlines"},
  {mac: "02:00:00:00:00:52", ip: "192.168.0.152", hostname: "evil‮gnp.exe"},
  {mac: "02:00:00:00:00:53", ip: "192.168.0.153", hostname: "esc\u001b[2Jape"},
  {mac: "02:00:00:00:00:54", ip: "192.168.0.154", hostname: ""},
  {mac: "02:00:00:00:00:55", ip: "192.168.0.155", hostname: $long}]' >"$DOTS_DEV_DIR/dns-leases.json"
open_dns
idle
wtype n
adding
echo "     forged leases: $(dns_state | jq -c '[.add.leases[] | [.name, .lines, .truncated]]')"
check "no lease draws a newline, a bidi mark or an escape" state_is 'all(.add.leases[]; (.name | test("[\n‮\u001b]")) | not) and all(.add.leases[]; .lines == 1)'
check "a lease with no hostname reads unnamed, the others one-lined" state_is '[.add.leases[0:4][].name] == ["two lines", "evilgnp.exe", "esc [2Jape", "unnamed"]'
check "the 200-character hostname is elided" state_is '.add.leases[4].truncated == true'
wtype -k Escape
until_ok 1000 state_is '.add == null'
close_dns
rm "$DOTS_DEV_DIR/dns-leases.json"

# The router does not answer: its rows keep their values, dim, and take no write; the carried rows work as before.
touch "$DOTS_DEV_DIR/dns-router-down"
open_dns
idle
echo "     down: $(dns_state | jq -c '{groups, footer, opacity: [.rows[] | .opacity]}')"
check "the router rows draw dimmed and the carried rows do not" state_is '[.rows[] | select(.key | startswith("router:")) | .opacity < 1] | all and length == 6'
check "and the carried rows at full opacity" state_is '[.rows[] | select(.key | startswith("carried:")) | .opacity == 1] | all'
check "router rows keep their last values" state_is '[.rows[] | select(.key | startswith("router:")) | .badge] == ["OPEN", "OPEN", "OPEN", "KID", "KID", "KID"]'
check "the line under HOME ROUTER reads router unreachable · as of HH:MM" state_is '.groups[1].line | test("^router unreachable · as of [0-9]{2}:[0-9]{2}$")'
check "the carried group has no such line" state_is '.groups[0].line == ""'
check "the footer gives both ages ($(dns_state | jq -c .footer))" state_is '.footer | test("^profiles as of [0-9]{2}:[0-9]{2} · router as of [0-9]{2}:[0-9]{2}$")'
wtype -k space
check "space on a carried row still logs kid carried:dev00iphone on" until_ok 3000 logged_is "kid carried:dev00iphone on" 1
idle
cursor_to router:02:00:00:00:00:05
before=$(calls)
wtype -k space
wtype n
wtype a
sleep 1
check "space, n and a on a dimmed router row run nothing ($(tail -n +$((before + 1)) "$log" | paste -sd'|'))" test "$(calls)" = "$before"
check "and open no add list or allow field" state_is '.add == null and .field == null'
close_dns

for t in "paper|DNS SHIELD › ADD DEVICE|router unreachable · as of" "artboard|DNS Shield › Add device|router unreachable · as of" "blueprint|DNS SHIELD // ADD DEVICE|✕ ROUTER UNREACHABLE · AS OF"; do
  IFS='|' read -r name head line <<<"$t"
  in_theme "$name"
  open_dns
  idle
  check "$name: the unreachable line reads $line HH:MM ($(dns_state | jq -c '.groups[1].line'))" state_is --arg l "$line" '.groups[1].line | startswith($l)'
  close_dns
  rm "$DOTS_DEV_DIR/dns-router-down"
  open_dns
  idle
  check "$name: with the router back the line and the dim clear by themselves" state_is '.groups[1].line == "" and all(.rows[]; .opacity == 1)'
  wtype n
  adding
  check "$name: the add heading reads $head ($(dns_state | jq -c .heading))" state_is --arg h "$head" '.heading == $h'
  wtype -k Escape
  until_ok 1000 state_is '.add == null'
  close_dns
  touch "$DOTS_DEV_DIR/dns-router-down"
done
rm "$DOTS_DEV_DIR/dns-router-down"
in_theme paper

exit $((fails > 0))
}
