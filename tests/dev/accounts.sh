#!/usr/bin/env bash
# Mod+U draws Claude accounts inside the island as board 8 does, with their limits, balances and usage from the collector's rows: the cache at once, then a full fetch; r and the refresh button fetch again, and nothing runs once it closes.
{
source "$(dirname "$0")/lib.sh"

# The shell runs whatever DOTS_ACCOUNTS names, so the check ends before any open unless that is the fake.
unit_env=$(systemctl --user show -p Environment --value "$DOTS_DEV_UNIT" | tr ' ' '\n')
if ! grep -qxF "DOTS_ACCOUNTS=$repo/bin/dev-fake-accounts" <<<"$unit_env"; then
  echo "FAIL the shell unit's DOTS_ACCOUNTS is the fake"
  exit 1
fi

log=$DOTS_DEV_DIR/accounts.log
# use refuses an account whose home is not a directory, so work has one.
mkdir -p "$XDG_STATE_HOME/dots/claude-accounts/work"
cat >"$XDG_STATE_HOME/dots/claude-accounts.json" <<EOF
{ "active": "main",
  "accounts": [
    { "id": "main", "label": "main", "home": "$HOME/.claude", "email": "a@b.c", "plan": "max" },
    { "id": "work", "label": "work", "home": "$XDG_STATE_HOME/dots/claude-accounts/work", "email": "x@y.z", "plan": "pro" } ] }
EOF

acc_state() { timeout 0.5 dots-call accounts state 2>/dev/null; }
state_is() { acc_state | jq -e "$@" >/dev/null 2>&1; }
island() { timeout 0.5 qs ipc call island state 2>/dev/null; }
island_is() { island | jq -e "$@" >/dev/null 2>&1; }
# The fake logs its arguments once per call, so a full fetch is an empty line.
calls() { [ -e "$log" ] && paste -sd'|' "$log"; }
ncalls() { if [ -e "$log" ]; then wc -l <"$log"; else echo 0; fi; }
fakes() { pgrep -f -- "$repo/bin/dev-fake-accounts" >/dev/null; }
# niri runs no binds for wtype's virtual keyboard, so the check spawns the bind's command through niri.
open_acc() { niri msg action spawn -- dots-call accounts toggle; until_ok 3000 state_is '.open and .settled and .keyboard'; }
close_acc() { wtype -k Escape; until_ok 3000 state_is '.drawing == false'; }
fetched() { until_ok "${1:-3000}" state_is '.busy == false and (.accounts | length) == 2'; }
# The colour of the pixel at x,y on the output, as lowercase hex without the #.
px() { grim -g "$1,$2 1x1" -t ppm - 2>/dev/null | tail -c3 | od -An -tx1 | tr -d ' \n'; }
# The pixel at the middle of a box {x, y, w, h}, as the colour px reads, so a drawn colour shows as pixels.
box_px() { px "$(jq -r '(.x + .w / 2) | floor' <<<"$1")" "$(jq -r '(.y + .h / 2) | floor' <<<"$1")"; }
# Pixels of box $1 within 24 of the hex colour $2 on each channel, so drawn text shows as pixels in its ink.
near_colour() {
  local geo
  geo=$(jq -r '"\(.x | floor),\(.y | floor) \(.w | ceil)x\(.h | ceil)"' <<<"$1")
  grim -s 1 -t ppm -g "$geo" - | node -e '
    const b = require("fs").readFileSync(0), hex = process.argv[1];
    const [r, g, bl] = [1, 3, 5].map((i) => parseInt(hex.slice(i, i + 2), 16));
    const head = b.toString("latin1").match(/^P6\s+(\d+)\s+(\d+)\s+(\d+)\s/), px = b.subarray(head[0].length);
    let n = 0;
    for (let i = 0; i < head[1] * head[2]; i++) if (Math.abs(px[i * 3] - r) <= 24 && Math.abs(px[i * 3 + 1] - g) <= 24 && Math.abs(px[i * 3 + 2] - bl) <= 24) n++;
    console.log(n);
  ' "$2"
}

timers_before=$(shell_status | jq .timers)
check "before Mod+U the surface is not loaded" state_is '.loaded == false'
check "and the fake has no calls" test "$(ncalls)" = 0

open_acc
fetched
echo "     accounts: $(acc_state | jq -c '{title, updated, accounts: [.accounts[] | [.id, .plan, .active, [.limits[] | .figure]]], balances: [.balances[].figure], usage: [.usage[].figure], captions, others}')"
read -r ow _ < <(niri msg -j outputs | jq -r '.[] | .logical | "\(.width) \(.height)"')
want=$((ow - 48 < 640 ? ow - 48 : 640))
check "Mod+U sets the surface to accounts and the island $want px wide ($(island | jq -c '{surface, width}'))" island_is --argjson w "$want" '.surface == "accounts" and .width == $w'
check "Mod+U draws 2 accounts, 6 balances and 3 usage rows" state_is '(.accounts | length) == 2 and (.balances | length) == 6 and (.usage | length) == 3'
check "no legend or key strip is in the state" state_is 'has("hint") == false and has("footer") == false and has("groups") == false'

# Board 8's header: the title, when the rows came, and a refresh button.
check "the header reads Accounts ($(acc_state | jq -c '[.title, .updated]'))" state_is '.title == "Accounts" and .updated == "updated just now"'
check "with a 32 px refresh button drawn as the nerd-font glyph U+F0450" state_is '.refreshButton | .glyph == "󰑐" and .w == 32 and .h == 32'
touch "$DOTS_DEV_DIR/accounts-aged"
wtype r
until_ok 3000 bash -c "[ \$(wc -l <'$log') -ge 3 ]"
check "rows fetched five minutes ago make the header read updated 5 min ago ($(acc_state | jq -c .updated))" until_ok 3000 state_is '.busy == false and .updated == "updated 5 min ago"'
rm "$DOTS_DEV_DIR/accounts-aged"
wtype r
until_ok 3000 bash -c "[ \$(wc -l <'$log') -ge 4 ]"
fetched

# Text draws on the island's own fill, in the island's ink.
island_fill=$(island | jq -r '.fill.color | ascii_downcase')
check "the card's fill is the island's ($(acc_state | jq -r .fillColor))" state_is --arg f "$island_fill" '.fillColor | ascii_downcase == $f'
check "a pixel of the card beside the heading is the island's fill #$island_fill" test "$(px "$(acc_state | jq -r '(.box.x + .box.w / 2) | floor')" "$(acc_state | jq -r '(.box.y + 4) | floor')")" = "${island_fill#\#}"
ink=$(acc_state | jq -r '.ink | ascii_downcase')
check "the heading draws pixels in the island's ink $ink" test "$(near_colour "$(acc_state | jq -c .titleBox)" "$ink")" -ge 10

# The active account: shaded, an inverted Active chip, and 5 h and Week bars 8 px high.
echo "     active: $(acc_state | jq -c '{active, bars: [.bars[] | del(.meterBox)]}')"
check "main is active, work is not" state_is '[.accounts[] | [.id, .active]] == [["main", true], ["work", false]]'
check "the active account is a tile named main, shaded at 12% of the ink" state_is '.active | .name == "main" and (.fill | ascii_downcase | test("^#1f"))'
check "its chip reads Active, filled with the ink and written in the island's fill" state_is '.ink as $i | .fillColor as $f | .active | .chip == "Active" and (.chipFill | ascii_downcase) == ($i | ascii_downcase) and (.chipInk | ascii_downcase) == ($f | ascii_downcase)'
check "the chip is drawn in the ink" test "$(box_px "$(acc_state | jq -c '.active.chipBox | .w = 8')")" = "${ink#\#}"
check "its first two bars are 5 h and Week, each 8 px high" state_is '[.bars[0:2][] | [.label, .height]] == [["5 h", 8], ["Week", 8]]'
check "5 h reads 34% and its bar is a third full, in the ink on a track at 16% of it" state_is '.ink as $i | .bars[0] | (.right | startswith("34%")) and ((.share - 0.34) | fabs) < 0.01 and (.trackFill | ascii_downcase | test("^#29")) and (.meterFill | ascii_downcase) == ($i | ascii_downcase)'
check "Week reads 61%" state_is '.bars[1].right | startswith("61%")'
check "the 5 h bar is drawn in the ink" test "$(box_px "$(acc_state | jq -c '.bars[0].meterBox | .w = 4')")" = "${ink#\#}"
check "work, the other account, is one line: its name, then 5 h and week as percents ($(acc_state | jq -c '.others'))" state_is '[.others[] | [.name, .line]] == [["work", "5 h 8% · week 12%"]]'
check "the cursor starts on work, the one row Enter acts on" state_is '.selected == "account:work" and .others[0].selected'

# Under BALANCES the balances draw as tiles, two to a row.
check "a BALANCES caption sits over the tiles ($(acc_state | jq -c '.captions'))" state_is '.captions == ["BALANCES"]'
check "the balances draw two to a row and stack in rows" state_is '[.tiles[] | select(.kind == "balance") | .box] as $b | $b[0].y == $b[1].y and $b[1].x >= $b[0].x + $b[0].w and $b[0].w == $b[1].w and $b[2].y > $b[0].y and $b[2].y == $b[3].y and $b[4].y > $b[2].y'
check "a tile is the ink at 7% with the name over its figure ($(acc_state | jq -c '[.tiles[] | select(.name == "OpenRouter") | [.name, .main, .rest, .fill]]'))" state_is 'any(.tiles[]; .name == "OpenRouter" and .main == "$3.10" and .rest == "of $10" and (.fill | ascii_downcase | test("^#12")))'
check "a Console grant reads what is left of it with its expiry ($(acc_state | jq -c '[.tiles[] | select(.name == "Anthropic main") | [.main, .rest, .reset]]'))" state_is 'any(.tiles[]; .name == "Anthropic main" and .main == "$38.87" and .rest == "of $205" and (.reset | test("^expires [0-9]+ [A-Z][a-z]{2}$")))'
check "Jina reads its tokens among the balances" state_is 'any(.tiles[]; .kind == "balance" and .name == "Jina" and .main == "953,604,107 tokens")'
check "Context7 reads its requests of the plan's, the device's key by that name ($(acc_state | jq -c '[.tiles[] | select(.name | startswith("Context7")) | [.name, .main, .rest]]'))" state_is 'any(.tiles[]; .kind == "usage" and .name == "Context7 main · this device" and .main == "240" and .rest == "of 1,000 requests")'
check "the fake ran --cached, then the full fetch, then the two r fetches ($(calls))" test "$(calls)" = "--cached|||"

# j and k move between the rows Enter acts on: work, then Context7 alt.
wtype j
check "j moves on to Context7 alt" until_ok 1000 state_is '.selected == "usage:Context7 alt" and any(.tiles[]; .name == "Context7 alt" and .selected)'
wtype -k Down
sleep 0.2
check "Down past the last stays there" state_is '.selected == "usage:Context7 alt"'

# Enter on a Context7 key runs dots context7 use, which finds no key in the nested pass store and changes nothing. The nested shell shares the live ~/.config, so the check never lets a use succeed: the live login keeps its bytes.
ctx7_active=$XDG_STATE_HOME/dots/context7-active
creds=${XDG_CONFIG_HOME:-$HOME/.config}/context7/credentials.json
creds_sum=$(sha256sum <"$creds" 2>/dev/null || true)
reg=$XDG_STATE_HOME/dots/claude-accounts.json
reg_sum=$(sha256sum <"$reg")
c7() { acc_state | jq -c '[.tiles[] | select(.name | startswith("Context7")) | .name]'; }
check "with no key picked, Context7 main is this device's ($(c7))" state_is '[.tiles[] | select(.name | startswith("Context7")) | .name] == ["Context7 main · this device", "Context7 alt"]'
wtype -k Return
sleep 1
check "Enter on a key the store lacks writes no choice" test ! -e "$ctx7_active"
check "and the device's key stays main ($(c7))" state_is '[.tiles[] | select(.name | startswith("Context7")) | .name] == ["Context7 main · this device", "Context7 alt"]'
check "and Accounts says nothing of Context7 ($(acc_state | jq -c .note))" eval "! acc_state | jq -e '.note | contains(\"Context7\")' >/dev/null"
check "and the live ctx7 login keeps its bytes" test "$(sha256sum <"$creds" 2>/dev/null || true)" = "$creds_sum"
check "and the registry keeps its bytes" test "$(sha256sum <"$reg")" = "$reg_sum"

wtype k
until_ok 1000 state_is '.selected == "account:work"'
wtype -k Return
active_is() { [ "$(jq -r .active "$reg")" = "$1" ]; }
check "Enter on work makes it the registry's active account" until_ok 3000 active_is work
check "and moves the Active tile to work ($(acc_state | jq -c '[.accounts[] | [.id, .active]]'))" until_ok 2000 state_is '[.accounts[] | [.id, .active]] == [["main", false], ["work", true]] and .active.name == "work" and [.others[].name] == ["main"]'
# The island draws Accounts, not its notice, while Accounts is open, so Accounts says it at its foot.
says_active() { state_is '.note == "Claude · work is active for new sessions"'; }
check "Accounts reads Claude · work is active for new sessions at its foot ($(acc_state | jq -c .note))" until_ok 3000 says_active

# A new cx session runs claude in work's home: cx runs the account wrapper at ~/.local/libexec/dots/claude, which runs ~/.local/bin/claude, so a scratch HOME holds this tree's wrapper and a stub claude that prints the CLAUDE_CONFIG_DIR it was given.
stub_home=$DOTS_DEV_DIR/stub-home
mkdir -p "$stub_home/.local/libexec/dots" "$stub_home/.local/bin"
cp "$repo/home/dot_local/libexec/dots/executable_claude" "$stub_home/.local/libexec/dots/claude"
printf '#!/bin/sh\nprintf "%%s\\n" "$CLAUDE_CONFIG_DIR"\n' >"$stub_home/.local/bin/claude"
chmod +x "$stub_home/.local/bin/claude"
cx_dir=$(HOME=$stub_home fish --no-config -c "source $repo/home/dot_config/fish/functions/cx.fish; cx")
check "a new cx session runs in work's home ($cx_dir)" test "$cx_dir" = "$XDG_STATE_HOME/dots/claude-accounts/work"

wtype r
check "r runs one more full fetch" until_ok 3000 bash -c "[ \"\$(paste -sd'|' '$log')\" = '--cached||||' ]"
fetched

# The near-full variant also takes 3 s, so the header shows the fetch running and a second r starts nothing.
touch "$DOTS_DEV_DIR/accounts-near-full"
wtype r
check "while a fetch runs the header reads refreshing… ($(acc_state | jq -c .updated))" until_ok 2000 state_is '.updated == "refreshing…" and .busy'
before=$(ncalls)
wtype r
fetched 6000
check "an r while the fetch ran started none ($(calls))" test "$(ncalls)" = "$before"
# main is no longer active after Enter on work, so its limits read on its one line.
check "a limit at 92% reads in the danger tone and one at 79% does not ($(acc_state | jq -c '[.accounts[0].limits[0, 1] | [.figure, .warning]]'))" state_is '.accounts[0].limits[0] | .figure == "92% used" and .warning == true'
check "and the 79% one does not" state_is '.accounts[0].limits[1] | .figure == "79% used" and .warning == false'
check "with work active the cursor is on main" state_is '.selected == "account:main"'
wtype -k Return
until_ok 3000 active_is main
fetched 6000
echo "     near full: $(acc_state | jq -c '[.bars[0:2][] | del(.meterBox) | {label, right, meterFill, rightColor, warning}]')"
check "a bar at 92% is in the danger tone, its figure too, and not in the ink" state_is '.ink as $i | .bars[0] | .warning and (.meterFill | ascii_downcase) != ($i | ascii_downcase) and .meterFill == .rightColor and (.right | startswith("92%"))'
check "a bar at 79% keeps the ink and the muted figure" state_is '.ink as $i | .bars[1] | (.warning | not) and (.meterFill | ascii_downcase) == ($i | ascii_downcase) and .meterFill != .rightColor and (.right | startswith("79%"))'
# The island may still be settling its height after the use, so the bar's pixel is read until it shows.
danger_drawn() {
  local tone
  tone=$(acc_state | jq -r '.bars[0].meterFill | ascii_downcase | ltrimstr("#")')
  [ -n "$tone" ] && [ "$(box_px "$(acc_state | jq -c '.bars[0].meterBox | .w = 4')")" = "$tone" ]
}
check "the danger bar is drawn in its tone ($(acc_state | jq -r '.bars[0].meterFill'))" until_ok 3000 danger_drawn

# A close and a second open while the slow fetch runs leave that one fetch to finish.
touch "$DOTS_DEV_DIR/accounts-slow-full"
before=$(ncalls)
close_acc
open_acc
until_ok 2000 bash -c "[ \$(wc -l <'$log') -ge $((before + 2)) ]"
close_acc
open_acc
fetched 15000
check "a second open while a fetch ran started no second fetch ($(calls))" test "$(ncalls)" = $((before + 2))
rm "$DOTS_DEV_DIR/accounts-near-full" "$DOTS_DEV_DIR/accounts-slow-full"

# A quick second Mod+U closes the card while the cache is read; that close starts no full fetch.
close_acc
touch "$DOTS_DEV_DIR/accounts-slow-cached"
before=$(ncalls)
niri msg action spawn -- dots-call accounts toggle
until_ok 3000 state_is '.open'
niri msg action spawn -- dots-call accounts toggle
until_ok 3000 state_is '.drawing == false'
sleep 1.5
check "a card closed while the cache was read starts no fetch ($(tail -n +$((before + 1)) "$log" | paste -sd'|'))" test "$(tail -n +$((before + 1)) "$log" | paste -sd'|')" = "--cached"
rm "$DOTS_DEV_DIR/accounts-slow-cached"
open_acc
fetched 6000

closed_at=$(ncalls)
close_acc
sleep 1
check "1 s after Esc the fake's log gains no new line ($(calls))" test "$(ncalls)" = "$closed_at"
check "within 10 s of Esc no dev-fake-accounts runs" until_ok 10000 eval '! fakes'
until_ok 33000 state_is '.loaded == false'
check "30 s after close shell status no longer lists accounts as loaded" bash -c "timeout 0.5 qs ipc call shell status | jq -e 'all(.loaded[]; . != \"accounts\")' >/dev/null"
check "and its timers are back to $timers_before ($(shell_status | jq .timers))" test "$(shell_status | jq .timers)" = "$timers_before"

# With no network the collector serves every source's cached rows as stale, and the card still opens with them. A cold open draws its card within 50 ms; its rows follow once the delegates are built, so that time is printed only.
touch "$DOTS_DEV_DIR/accounts-offline"
cold=()
card=()
for i in 1 2 3 4 5; do
  until_ok 33000 state_is '.loaded == false'
  niri msg action spawn -- dots-call accounts toggle
  until_ok 3000 state_is '.openMs != null and .keyboard and .settled'
  cold+=("$(acc_state | jq .openMs)")
  card+=("$(acc_state | jq .cardMs)")
  fetched 6000
  [ "$i" = 5 ] || close_acc
done
echo "     cold opens: card ${card[*]} ms, rows ${cold[*]} ms"
timed() { jq -e 'type == "number" and . > 0' <<<"$1" >/dev/null; }
within() { jq -e --argjson most "$2" 'type == "number" and . > 0 and . <= $most' <<<"$1" >/dev/null; }
for ms in "${card[@]}"; do
  check "a cold open draws its card within 50 ms ($ms ms)" within "$ms" 50
done
for ms in "${cold[@]}"; do
  check "and its rows are timed to their first frame ($ms ms)" timed "$ms"
done
echo "     offline: $(acc_state | jq -c '{updated, accounts: [.accounts[].note], providers: [(.balances + .usage)[] | [.note, .error]]}')"
check "offline, the header reads updated 2 h ago" state_is '.updated == "updated 2 h ago"'
check "offline, every account reads stale · as of HH:MM" state_is 'all(.accounts[]; .note | test("^stale · as of [0-9]{2}:[0-9]{2}$"))'
check "every balance and usage tile keeps its figure with as of HH:MM, not in the ink" state_is '.ink as $i | all(.tiles[]; (.note | test("^as of [0-9]{2}:[0-9]{2}$")) and .main != "" and (.noteColor | ascii_downcase) != ($i | ascii_downcase))'
check "nothing is drawn as an error" state_is 'all((.balances + .usage)[]; .error == false)'
# Every drawn text of a tile ends inside the card: a stale row once ran its reset past the right border.
inside() { state_is '.box as $c | all(.tiles[]; .right <= $c.x + $c.w + 0.5) and all(.others[]; .right <= $c.x + $c.w + 0.5)'; }
edges() { acc_state | jq -c '[(.box.x + .box.w | floor), ([.tiles[].right] | max | floor)]'; }
check "offline, every tile stays inside the card (card, tiles right: $(edges))" inside
check "offline, no note is cut short ($(acc_state | jq -c '[.tiles[] | select(.noteElided) | .note]'))" state_is 'all(.tiles[]; .noteElided == false)'
# A reset column once kept 50 px idle while a figure beside its note was cut short.
check "offline, Anthropic alt's figure is whole beside its note ($(acc_state | jq -c '[.tiles[] | select(.name == "Anthropic alt") | [.main, .mainElided]]'))" state_is 'any(.tiles[]; .name == "Anthropic alt" and .mainElided == false)'
rm "$DOTS_DEV_DIR/accounts-offline"
close_acc

# Rows from a file anyone can write: a 200-character unit and label, a stale grant with its expiry, and a thousand balances.
node -e '
  const now = Date.now(), iso = (t) => new Date(t).toISOString();
  const row = (o) => Object.assign({ account: null, limit: null, unit: "USD", resets_at: null, as_of: iso(now - 7200e3), state: "stale", reason: "network" }, o);
  const rows = [
    row({ provider: "claude", label: "work", account: "work", metric: "5-hour", kind: "percent", value: 12, limit: 100, unit: "%", reason: "expired" }),
    row({ provider: "anthropic", label: "Anthropic main", metric: "grant", kind: "money", value: 38.87, limit: 205, resets_at: iso(now + 14 * 86400e3) }),
    row({ provider: "elevenlabs", label: "ElevenLabs", metric: "characters", kind: "count", value: 1, limit: 2, unit: "L".repeat(200), resets_at: iso(now + 12 * 86400e3) }),
    row({ provider: "x", label: "W".repeat(200), metric: "balance", kind: "money", value: 123456789.12, limit: 999999999 }),
  ];
  for (let i = 0; i < 1000; i++) rows.push(row({ provider: "p" + i, label: "P" + i, metric: "balance", kind: "money", value: i }));
  console.log(JSON.stringify(rows));
' >"$DOTS_DEV_DIR/accounts-rows.json"
out_h=$(niri msg -j outputs | jq -r 'first(.[]).logical.height')
open_acc
fetched 6000
check "forged rows stay inside the card (card, tiles right: $(edges))" inside
check "no note is cut short ($(acc_state | jq -c '[.tiles[] | select(.noteElided) | .note]'))" state_is 'all(.tiles[]; .noteElided == false)'
check "the expired account's line ends inside the card, whole or in an ellipsis ($(acc_state | jq -c '[.others[] | .line]'))" state_is 'any(.others[]; .line | test("stale"))'
check "a thousand rows draw at most 16 tiles, on a card no taller than the screen ($(acc_state | jq -c '[(.tiles | length), (.box.h | floor)]') of $out_h)" state_is --argjson h "$out_h" '(.tiles | length) <= 16 and .box.h <= $h'
close_acc
# The same rows again keep their delegates, which must draw their notes after the card was hidden.
open_acc
fetched 6000
check "reopened with the same rows, every tile draws its note ($(acc_state | jq -c '[.tiles[].note] | unique'))" state_is '[.tiles[].note] | length > 0 and all(test("as of"; "i"))'
close_acc
rm "$DOTS_DEV_DIR/accounts-rows.json"

exit $((fails > 0))
}
