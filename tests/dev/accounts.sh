#!/usr/bin/env bash
# Mod+U draws Claude accounts with their limits, balances and usage from the collector's rows: the cache at once, then a full fetch; r fetches again, and nothing runs once it closes.
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
# The fake logs its arguments once per call, so a full fetch is an empty line.
calls() { [ -e "$log" ] && paste -sd'|' "$log"; }
ncalls() { if [ -e "$log" ]; then wc -l <"$log"; else echo 0; fi; }
fakes() { pgrep -f -- "$repo/bin/dev-fake-accounts" >/dev/null; }
# niri runs no binds for wtype's virtual keyboard, so the check spawns the bind's command through niri.
open_acc() { niri msg action spawn -- dots-call accounts toggle; until_ok 3000 state_is '.open and .settled and .keyboard'; }
close_acc() { wtype -k Escape; until_ok 3000 state_is '.drawing == false'; }
fetched() { until_ok "${1:-3000}" state_is '.busy == false and (.accounts | length) == 2'; }
# Pixels of geometry $1 farther than 12 from the hex colour $2, so a drawn label shows as pixels off the card's colour.
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
group_geo() { acc_state | jq -r '.groups[0] | "\(.x | floor),\(.y | floor) \(.w | ceil)x\(.h | ceil)"'; }

timers_before=$(shell_status | jq .timers)
check "before Mod+U the surface is not loaded" state_is '.loaded == false'
check "and the fake has no calls" test "$(ncalls)" = 0

open_acc
fetched
echo "     accounts: $(acc_state | jq -c '{accounts: [.accounts[] | [.id, .plan, .active, [.limits[] | .figure]]], balances: [.balances[].figure], usage: [.usage[].figure], footer, groups: [.groups[].text]}')"
check "Mod+U draws 2 accounts, 6 balances and 3 usage rows" state_is '(.accounts | length) == 2 and (.balances | length) == 6 and (.usage | length) == 3'
check "Context7 reads its requests of the plan's ($(acc_state | jq -c '[.rows[] | select(.name == "Context7 main") | [.figure, .reset]]'))" state_is 'any(.rows[]; .kind == "usage" and .name == "Context7 main" and .figure == "240 of 1,000 requests")'
check "a Console grant reads what is left of it, with its expiry under the name ($(acc_state | jq -c '[.rows[] | select(.name == "Anthropic main") | [.figure, .reset]]'))" state_is 'any(.rows[]; .name == "Anthropic main" and .figure == "$38.87 of $205 left" and (.reset | test("^expires [0-9]+ [A-Z][a-z]{2}$")))'
check "Jina reads its tokens among the balances" state_is 'any(.rows[]; .kind == "balance" and .name == "Jina" and .figure == "953,604,107 tokens")'
check "main is active, work is not" state_is '[.accounts[] | [.id, .active]] == [["main", true], ["work", false]]'
check "main's 5-hour reads 34% used, resets 17:00 ($(acc_state | jq -c '.accounts[0].limits[0]'))" state_is '.accounts[0].limits[0] | .name == "5-hour" and .figure == "34% used" and .reset == "resets 17:00" and .warning == false'
check "the card draws that row as 34% and resets 17:00" state_is 'any(.rows[]; .kind == "limit" and .name == "5-hour" and .figure == "34%" and .reset == "resets 17:00")'
check "the fake ran --cached, then the full fetch ($(calls))" test "$(calls)" = "--cached|"
check "the footer reads as of HH:MM ($(acc_state | jq -c .footer))" state_is '.footer | test("^as of [0-9]{2}:[0-9]{2}$")'
check "the cursor starts on main" state_is '.selected == "account:main"'
wtype j
check "j moves past main's limits to work" until_ok 1000 state_is '.selected == "account:work"'
wtype -k Down
check "Down moves on to the first balance" until_ok 1000 state_is '.selected == "balance:DeepSeek"'

# Enter on a provider row runs nothing: the registry keeps its bytes and the island says nothing about Claude.
reg=$XDG_STATE_HOME/dots/claude-accounts.json
island() { timeout 0.5 qs ipc call island state 2>/dev/null; }
reg_sum=$(sha256sum <"$reg")
wtype -k Return
sleep 1
check "Enter on DeepSeek leaves the registry's bytes as they were" test "$(sha256sum <"$reg")" = "$reg_sum"
check "and the island says nothing of Claude ($(island | jq -c .text))" eval "! island | jq -e '.text | contains(\"Claude\")' >/dev/null"
check "and main stays active" state_is '[.accounts[] | [.id, .active]] == [["main", true], ["work", false]]'

wtype k
until_ok 1000 state_is '.selected == "account:work"'
wtype -k Return
active_is() { [ "$(jq -r .active "$reg")" = "$1" ]; }
check "Enter on work makes it the registry's active account" until_ok 3000 active_is work
check "and moves ACTIVE to work ($(acc_state | jq -c '[.accounts[] | [.id, .active]]'))" until_ok 2000 state_is '[.accounts[] | [.id, .active]] == [["main", false], ["work", true]]'
check "the drawn ACTIVE mark sits on work's row" state_is '[.rows[] | select(.kind == "account") | [.name, .active]] == [["main", ""], ["work", "ACTIVE"]]'
island_says() { island | jq -e '.text == "Claude · work is active for new sessions"' >/dev/null; }
check "the island reads Claude · work is active for new sessions ($(island | jq -c .text))" until_ok 3000 island_says

# Enter on a Context7 key runs dots context7 use, which finds no key in the nested pass store and changes nothing. The nested shell shares the live ~/.config, so the check never lets a use succeed: the live login keeps its bytes.
ctx7_active=$XDG_STATE_HOME/dots/context7-active
creds=${XDG_CONFIG_HOME:-$HOME/.config}/context7/credentials.json
creds_sum=$(sha256sum <"$creds" 2>/dev/null || true)
c7() { acc_state | jq -c '[.rows[] | select(.name | startswith("Context7")) | [.name, .active]]'; }
check "with no key picked, Context7 main reads ACTIVE ($(c7))" state_is '[.rows[] | select(.name | startswith("Context7")) | [.name, .active]] == [["Context7 main", "ACTIVE"], ["Context7 alt", ""]]'
for _ in $(seq 12); do state_is '.selected == "usage:Context7 alt"' && break; wtype -k Down; sleep 0.1; done
check "Down reaches Context7 alt" state_is '.selected == "usage:Context7 alt"'
wtype -k Return
sleep 1
check "Enter on a key the store lacks writes no choice" test ! -e "$ctx7_active"
check "and ACTIVE stays on main ($(c7))" state_is '[.rows[] | select(.name | startswith("Context7")) | [.name, .active]] == [["Context7 main", "ACTIVE"], ["Context7 alt", ""]]'
check "and the island says nothing of Context7 ($(island | jq -c .text))" eval "! island | jq -e '.text | contains(\"Context7\")' >/dev/null"
check "and the live ctx7 login keeps its bytes" test "$(sha256sum <"$creds" 2>/dev/null || true)" = "$creds_sum"

# A new cx session runs claude in work's home: a stub claude first on PATH prints the CLAUDE_CONFIG_DIR it was given.
mkdir -p "$DOTS_DEV_DIR/stub"
printf '#!/bin/sh\nprintf "%%s\\n" "$CLAUDE_CONFIG_DIR"\n' >"$DOTS_DEV_DIR/stub/claude"
chmod +x "$DOTS_DEV_DIR/stub/claude"
cx_dir=$(PATH=$DOTS_DEV_DIR/stub:$PATH fish --no-config -c "source $repo/home/dot_config/fish/functions/cx.fish; cx")
check "a new cx session runs in work's home ($cx_dir)" test "$cx_dir" = "$XDG_STATE_HOME/dots/claude-accounts/work"

wtype r
check "r runs one more full fetch" until_ok 3000 bash -c "[ \"\$(paste -sd'|' '$log')\" = '--cached||' ]"
fetched

# The near-full variant also takes 3 s, so the footer shows the fetch running and a second r starts nothing.
touch "$DOTS_DEV_DIR/accounts-near-full"
wtype r
check "while a fetch runs the footer reads refreshing… ($(acc_state | jq -c .footer))" until_ok 2000 state_is '.footer == "refreshing…" and .busy'
wtype r
fetched 6000
check "an r while the fetch ran started none ($(calls))" test "$(ncalls)" = 4
check "a limit at 92% warns and one at 79% does not ($(acc_state | jq -c '[.accounts[0].limits[0, 1] | [.figure, .warning]]'))" state_is '.accounts[0].limits[0] | .figure == "92% used" and .warning == true'
check "and the 79% one does not" state_is '.accounts[0].limits[1] | .figure == "79% used" and .warning == false'
check "the 92% row draws its warning triangle" state_is 'any(.rows[]; .kind == "limit" and .figure == "92%" and .warning) and ([.rows[] | select(.warning)] | length) == 1'

# A close and a second open while the slow fetch runs leave that one fetch to finish.
before=$(ncalls)
close_acc
open_acc
until_ok 2000 bash -c "[ \$(wc -l <'$log') -ge $((before + 2)) ]"
close_acc
open_acc
fetched 6000
check "a second open while a fetch ran started no second fetch ($(calls))" test "$(ncalls)" = $((before + 2))
rm "$DOTS_DEV_DIR/accounts-near-full"

check "the Claude group label reads Claude ($(acc_state | jq -c '.groups[0].text'))" state_is '.groups[0].text == "Claude"'
px=$(off_colour "$(group_geo)" "#FFFFFF")
check "the label's strip $(group_geo) draws $px px off the card's #FFFFFF" test "$px" -ge 10

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

close_acc
check "within 10 s of Esc no dev-fake-accounts runs" until_ok 10000 eval '! fakes'
until_ok 33000 state_is '.loaded == false'
check "30 s after close shell status no longer lists accounts as loaded" bash -c "timeout 0.5 qs ipc call shell status | jq -e 'all(.loaded[]; . != \"accounts\")' >/dev/null"
check "and its timers are back to $timers_before ($(shell_status | jq .timers))" test "$(shell_status | jq .timers)" = "$timers_before"

# With no network the collector serves every source's cached rows as stale, and the card still opens with them. A cold open draws its card within 50 ms (#166PQ300); its rows follow once the 17 delegates are built, 45 to 80 ms, so that time is printed only.
touch "$DOTS_DEV_DIR/accounts-offline"
cold=()
card=()
for i in 1 2 3 4 5; do
  until_ok 33000 state_is '.loaded == false'
  niri msg action spawn -- dots-call accounts toggle
  until_ok 3000 state_is '.openMs != null'
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
echo "     offline: $(acc_state | jq -c '{accounts: [.accounts[].note], providers: [(.balances + .usage)[] | [.note, .error]]}')"
check "offline, every account reads stale · as of HH:MM" state_is 'all(.accounts[]; .note | test("^stale · as of [0-9]{2}:[0-9]{2}$"))'
check "every balance and usage row keeps its figure with as of HH:MM" state_is 'all((.balances + .usage)[]; (.note | test("^as of [0-9]{2}:[0-9]{2}$")) and .figure != "")'
check "nothing is drawn as an error" state_is 'all((.balances + .usage)[]; .error == false) and all(.rows[]; (.note | startswith("✕")) | not)'
# Every drawn text of a row ends inside the card: a stale row once ran its reset past the right border.
inside() { state_is '.cardBox as $c | all(.rows[]; .right <= $c.x + $c.w + 0.5)'; }
edges() { acc_state | jq -c '[(.cardBox.x + .cardBox.w | floor), ([.rows[].right] | max | floor)]'; }
check "offline, every row stays inside the card (card, rows right: $(edges))" inside
check "offline, no note is cut short ($(acc_state | jq -c '[.rows[] | select(.noteElided) | .note]'))" state_is 'all(.rows[]; .noteElided != true)'
# A reset column once kept 50 px idle while a figure beside its note was cut short; ElevenLabs' longer figure fills its row and may elide.
check "offline, Anthropic alt's figure is whole beside its bar and note ($(acc_state | jq -c '[.rows[] | select(.name == "Anthropic alt") | [.figure, .figureElided]]'))" state_is 'any(.rows[]; .name == "Anthropic alt" and .figureElided == false)'
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
check "forged rows stay inside the card (card, rows right: $(edges))" inside
check "no note is cut short ($(acc_state | jq -c '[.rows[] | select(.noteElided) | .note]'))" state_is 'all(.rows[]; .noteElided != true)'
check "the expired account's note is whole or ends in an ellipsis, never cut at its start ($(acc_state | jq -c '[.rows[] | select(.kind == "account") | .note]'))" state_is 'any(.rows[]; .kind == "account" and (.note | test("^stale")) and .noteCut == false)'
check "a thousand rows draw at most 50, on a card no taller than the screen ($(acc_state | jq -c '[(.rows | length), (.cardBox.h | floor)]') of $out_h)" state_is --argjson h "$out_h" '(.rows | length) <= 50 and .cardBox.h <= $h'
close_acc
# The same rows again keep their delegates, which must draw their notes after the card was hidden.
open_acc
fetched 6000
check "reopened with the same rows, every balance and usage row draws its note ($(acc_state | jq -c '[.rows[] | select(.kind == "balance" or .kind == "usage") | .note] | unique'))" state_is '[.rows[] | select(.kind == "balance" or .kind == "usage") | .note] | length > 0 and all(test("as of"; "i"))'
close_acc
rm "$DOTS_DEV_DIR/accounts-rows.json"

exit $((fails > 0))
}
