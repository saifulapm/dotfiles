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
mkdir -p "$XDG_STATE_HOME/dots"
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
status_theme() { shell_status | jq -e --arg t "$1" '.theme == $t and .transition == ""' >/dev/null; }
in_theme() { "$repo/bin/dots" theme "$1" >/dev/null; until_ok 4000 status_theme "$1"; }
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
check "Mod+U draws 2 accounts, 5 balances and 2 usage rows" state_is '(.accounts | length) == 2 and (.balances | length) == 5 and (.usage | length) == 2'
check "main is active, work is not" state_is '[.accounts[] | [.id, .active]] == [["main", true], ["work", false]]'
check "main's 5-hour reads 34% used, resets 17:00 ($(acc_state | jq -c '.accounts[0].limits[0]'))" state_is '.accounts[0].limits[0] | .name == "5-hour" and .figure == "34% used" and .reset == "resets 17:00" and .warning == false'
check "Paper draws that row as 34% and resets 17:00" state_is 'any(.rows[]; .kind == "limit" and .name == "5-hour" and .figure == "34%" and .reset == "resets 17:00")'
check "the fake ran --cached, then the full fetch ($(calls))" test "$(calls)" = "--cached|"
check "the footer reads as of HH:MM ($(acc_state | jq -c .footer))" state_is '.footer | test("^as of [0-9]{2}:[0-9]{2}$")'
check "the cursor starts on main" state_is '.selected == "account:main"'
wtype j
check "j moves past main's limits to work" until_ok 1000 state_is '.selected == "account:work"'
wtype -k Down
check "Down moves on to the first balance" until_ok 1000 state_is '.selected == "balance:DeepSeek"'

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

for t in "paper|CLAUDE|#FAF6EC" "artboard|Claude|#FFFFFF" "blueprint|CLAUDE|#0A1526"; do
  IFS='|' read -r name label card <<<"$t"
  close_acc
  in_theme "$name"
  open_acc
  fetched 6000
  check "$name: the Claude group label reads $label ($(acc_state | jq -c '.groups[0].text'))" state_is --arg l "$label" '.groups[0].text == $l'
  px=$(off_colour "$(group_geo)" "$card")
  check "$name: the label's strip $(group_geo) draws $px px off the card's $card" test "$px" -ge 10
done

close_acc
check "within 10 s of Esc no dev-fake-accounts runs" until_ok 10000 eval '! fakes'
until_ok 33000 state_is '.loaded == false'
check "30 s after close shell status no longer lists accounts as loaded" bash -c "timeout 0.5 qs ipc call shell status | jq -e 'all(.loaded[]; . != \"accounts\")' >/dev/null"
check "and its timers are back to $timers_before ($(shell_status | jq .timers))" test "$(shell_status | jq .timers)" = "$timers_before"

exit $((fails > 0))
}
