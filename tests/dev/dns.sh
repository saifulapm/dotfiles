#!/usr/bin/env bash
# Mod+Shift+D draws DNS Shield's carried and router devices from dots-dns state; space, 1-4 and a write through dots-dns and the card reads state again.
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
# The fake logs every call, state reads included, so a write is counted by its exact line.
logged() { if [ -e "$log" ]; then grep -cxF -- "$1" "$log"; else echo 0; fi; }
logged_is() { [ "$(logged "$1")" = "$2" ]; }
fakes() { pgrep -f -- "$repo/bin/dev-fake-dns" >/dev/null; }
status_theme() { shell_status | jq -e --arg t "$1" '.theme == $t and .transition == ""' >/dev/null; }
in_theme() { "$repo/bin/dots" theme "$1" >/dev/null; until_ok 4000 status_theme "$1"; }
# niri runs no binds for wtype's virtual keyboard, so the check spawns the bind's command through niri.
bind=$(sed -n 's/^\s*Mod+Shift+D [^{]*{ spawn \(.*\); }$/\1/p' "$repo/home/dot_config/niri/binds.kdl" | tr -d '"')
open_dns() { niri msg action spawn -- $bind; until_ok 3000 state_is '.open and .settled and .keyboard'; }
close_dns() { wtype -k Escape; until_ok 3000 state_is '.drawing == false'; }
idle() { until_ok "${1:-3000}" state_is '.busy == false and (.rows | length) > 0'; }
cursor_to() { local i; for i in $(seq 1 10); do state_is --arg k "$1" '.cursor == $k' && return 0; wtype j; sleep 0.1; done; state_is --arg k "$1" '.cursor == $k'; }
row() { dns_state | jq -c --arg k "$1" '.rows[] | select(.key == $k)'; }
badge_is() { state_is --arg k "$1" --arg b "$2" 'any(.rows[]; .key == $k and .badge == $b)'; }
# Pixels of geometry $1 farther than 12 from the hex colour $2, so a drawn strip shows as pixels off the card's colour.
off_colour() {
  grim -s 1 -t ppm -g "$1" - | node -e '
    const b = require("fs").readFileSync(0), hex = process.argv[1];
    const [r, g, bl] = [1, 3, 5].map((i) => parseInt(hex.slice(i, i + 2), 16));
    const head = b.toString("latin1").match(/^P6\s+(\d+)\s+(\d+)\s+(\d+)\s/), px = b.subarray(head[0].length);
    let n = 0;
    for (let i = 0; i < head[1] * head[2]; i++) if (Math.abs(px[i * 3] - r) > 12 || Math.abs(px[i * 3 + 1] - g) > 12 || Math.abs(px[i * 3 + 2] - bl) > 12) n++;
    console.log(n);
  ' "$2"
}
cursor_geo() { dns_state | jq -r '.cursorBox | "\(.x | floor),\(.y | floor) \(.w | ceil)x\(.h | ceil)"'; }

ipad=carried:dev00ipad
sister=router:02:00:00:00:00:04
tv=router:02:00:00:00:00:05

timers_before=$(shell_status | jq .timers)
check "the bind spawns dots-call dns toggle ($bind)" test "$bind" = "dots-call dns toggle"
check "before Mod+Shift+D the surface is not loaded" state_is '.loaded == false'

open_dns
idle
echo "     rows: $(dns_state | jq -c '[.rows[] | [.name, .badge, .age]]')"
check "Mod+Shift+D draws 3 carried and 5 router rows" state_is '.carried == 3 and .router == 5 and (.rows | length) == 8'
check "the rows read the board's names, badges and ages" state_is '[.rows[] | [.name, .badge, .age]] == [["Saiful'"'"'s iPhone", "OPEN", "—"], ["iPad", "KID", "2m"], ["Wife'"'"'s iPhone", "OPEN", "—"], ["macbook", "OPEN", "—"], ["nuc", "OPEN", "—"], ["mini", "OPEN", "—"], ["Sister'"'"'s phone", "KID", "41m"], ["Living-room TV", "KID", "1h"]]'
check "Paper labels the groups CARRIED PROFILE · 3 and HOME ROUTER · 5 ($(dns_state | jq -c '[.groups[].text]'))" state_is '[.groups[].text] == ["CARRIED PROFILE · 3", "HOME ROUTER · 5"]'
check "the footer reads as of HH:MM ($(dns_state | jq -c .footer))" state_is '.footer | test("^as of [0-9]{2}:[0-9]{2}$")'
check "the cursor starts on the first device" state_is '.cursor == "carried:dev00iphone"'

wtype j
check "j moves to the iPad" until_ok 1000 state_is --arg k "$ipad" '.cursor == $k'
echo "     pane: $(dns_state | jq -c .pane)"
check "the iPad's pane reads its path, KID and Gambling off" state_is '.pane | .name == "iPad" and .path == "Carried profile · uBlockDNS" and .badge == "KID" and ([.categories[] | "\(.n) \(.label) \(.value)"] == ["1 YouTube ON", "2 Social ON", "3 Adult ON", "4 Gambling OFF"])'
check "and its allow list and recent blocks" state_is '.pane | .allow == ["khanacademy.org", "wikipedia.org"] and ([.blocks[].domain] == ["youtube.com", "i.ytimg.com", "tiktok.com"])'

wtype -k space
check "space on the iPad logs one kid $ipad off" until_ok 3000 logged_is "kid $ipad off" 1
check "and its drawn row reads OPEN ($(row "$ipad"))" until_ok 3000 badge_is "$ipad" OPEN
check "its pane shows only its blocks and how to turn Kid on" until_ok 1000 state_is '.pane.categories == [] and .pane.allow == [] and .pane.hint == "space turns Kid mode on"'
idle
wtype -k space
check "space again logs one kid $ipad on" until_ok 3000 logged_is "kid $ipad on" 1
check "and the row reads KID" until_ok 3000 badge_is "$ipad" KID
check "with the remembered categories back ($(dns_state | jq -c '[.pane.categories[].value]'))" until_ok 1000 state_is '[.pane.categories[].value] == ["ON", "ON", "ON", "OFF"]'

# Each write takes 1 s here, so the second space comes while the first runs, and must wait for it rather than be lost.
idle
touch "$DOTS_DEV_DIR/dns-slow"
wtype -k space
wtype -k space
both() { logged_is "kid $ipad off" 2 && logged_is "kid $ipad on" 2; }
check "two quick spaces while a write runs log off, then on" until_ok 6000 both
idle 4000
check "and the iPad reads KID after both" badge_is "$ipad" KID
check "the off ran before the on ($(grep -n "^kid $ipad" "$log" | tail -2 | paste -sd' '))" test "$(grep "^kid $ipad" "$log" | tail -2 | paste -sd'|')" = "kid $ipad off|kid $ipad on"
rm "$DOTS_DEV_DIR/dns-slow"

wtype j
check "j moves on to Wife's iPhone" until_ok 1000 state_is '.cursor == "carried:dev00wife"'
wtype j
check "and j crosses into the router group at macbook" until_ok 1000 state_is '.cursor == "router:02:00:00:00:00:01"'

cursor_to "$sister"
check "Sister's phone reads Home router with all four categories on" state_is '.pane | .path == "Home router" and .badge == "KID" and ([.categories[].value] == ["ON", "ON", "ON", "ON"])'
wtype -k space
check "space on Sister's phone logs one kid $sister off" until_ok 3000 logged_is "kid $sister off" 1
check "and its row reads OPEN" until_ok 3000 badge_is "$sister" OPEN
idle

wtype j
check "j moves on to the Living-room TV ($(dns_state | jq -c .cursor))" until_ok 1000 state_is --arg k "$tv" '.cursor == $k'
wtype 1234
sleep 1
check "1-4 on a router row log no category write ($(grep -c '^category' "$log"))" test "$(grep -c '^category' "$log")" = 0
check "and leave its categories on ($(dns_state | jq -c '[.pane.categories[].value]'))" state_is '[.pane.categories[].value] == ["ON", "ON", "ON", "ON"]'

wtype a
check "a opens the allow field, empty" until_ok 1000 state_is '.field == ""'
wtype khanacademy.org
check "the field takes the typed domain ($(dns_state | jq -c .field))" until_ok 1000 state_is '.field == "khanacademy.org"'
check "and typing in it moved nothing" state_is --arg k "$tv" '.cursor == $k and .open'
wtype -k Return
check "Enter logs one allow $tv khanacademy.org" until_ok 3000 logged_is "allow $tv khanacademy.org" 1
check "and the drawn allow list holds it ($(dns_state | jq -c .pane.allow))" until_ok 3000 state_is '.field == null and (.pane.allow | index("khanacademy.org")) != null'
wtype a
until_ok 1000 state_is '.field == ""'
wtype -k Escape
check "Esc in the field closes the field, not the card" until_ok 1000 state_is '.field == null and .open'

# The same data again keeps the delegates, which must draw their rows after the card was hidden.
idle
before=$(dns_state | jq -c '[.rows[] | [.name, .badge]]')
close_dns
open_dns
idle
check "reopened with identical data, the drawn rows read back the same ($(dns_state | jq -c '[.rows[] | [.name, .badge]]'))" test "$(dns_state | jq -c '[.rows[] | [.name, .badge]]')" = "$before"
check "and the pane is drawn" state_is '.pane.name != ""'

for t in "paper|CARRIED PROFILE · 3|HOME ROUTER · 5|#FAF6EC" "artboard|Carried profile · 3|Home router · 5|#FFFFFF" "blueprint|CARRIED PROFILE · 3|HOME ROUTER · 5|#0A1526"; do
  IFS='|' read -r name carried router card <<<"$t"
  close_dns
  in_theme "$name"
  open_dns
  idle
  check "$name: the groups read $carried and $router ($(dns_state | jq -c '[.groups[].text]'))" state_is --arg a "$carried" --arg b "$router" '[.groups[].text] == [$a, $b]'
  px=$(off_colour "$(cursor_geo)" "$card")
  check "$name: the cursor row's strip $(cursor_geo) draws $px px off the card's $card, over half of it" test "$px" -ge 10000
done
in_theme paper
close_dns

# Names from a state file anyone on the network can write: a newline, a bidi override, an escape sequence, an empty name and 200 characters.
dns_state_file=$DOTS_DEV_DIR/dns-state.json
jq --arg long "$(printf 'W%.0s' $(seq 1 200))" '
  .devices[0].name = "two\nlines" | .devices[1].name = "evil‮gnp.exe" | .devices[2].name = "esc\u001b[2Jape"
  | .devices[3].name = "" | .devices[4].name = $long' "$dns_state_file" >"$dns_state_file.tmp"
mv "$dns_state_file.tmp" "$dns_state_file"
open_dns
idle
echo "     forged: $(dns_state | jq -c '[.rows[0:5][] | [.name, .lines, .truncated]]')"
check "no drawn name holds a newline, a bidi mark or an escape" state_is 'all(.rows[]; (.name | test("[\n‮\u001b]")) | not)'
check "each forged name draws on one line" state_is 'all(.rows[]; .lines == 1)'
check "the newline and the escape read as spaces" state_is '[.rows[0, 2].name] == ["two lines", "esc [2Jape"]'
check "the empty name reads as its MAC" state_is '.rows[3].name == "02:00:00:00:00:01"'
check "the 200-character name is elided" state_is '.rows[4].truncated == true'
close_dns

check "within 10 s of Esc no dev-fake-dns runs" until_ok 10000 eval '! fakes'
until_ok 33000 state_is '.loaded == false'
check "30 s after close shell status no longer lists dns as loaded" bash -c "timeout 0.5 qs ipc call shell status | jq -e 'all(.loaded[]; . != \"dns\")' >/dev/null"
check "and its timers are back to $timers_before ($(shell_status | jq .timers))" test "$(shell_status | jq .timers)" = "$timers_before"

exit $((fails > 0))
}
