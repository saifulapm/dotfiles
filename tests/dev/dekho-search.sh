#!/usr/bin/env bash
# Dekho's Home searches as the text is typed: 250 ms after the keys stop, from 2 characters, the field keeps the keys, the newest query's answer is the one drawn, and Enter and Esc work as before.
{
source "$(dirname "$0")/lib.sh"

dekho_qml=$repo/shell/dekho.qml
entry=$repo/home/dot_local/share/applications/dekho.desktop
work=$(mktemp -d)
cleanup() { rm -rf "$work"; }
log=$work/dekho.log
fake_log=$DOTS_DEV_DIR/dekho.log

dekho_state() { timeout 0.5 qs ipc -p "$dekho_qml" call dekho state 2>/dev/null; }
dekho_is() { dekho_state | jq -e "$@" >/dev/null 2>&1; }
dekho_windows() { niri msg -j windows | jq '[.[] | select(.app_id == "dekho")] | length'; }
dekho_up() { [ "$(dekho_windows)" = 1 ] && dekho_is '.firstFrameMs != null'; }
dekho_gone() { [ "$(dekho_windows)" = 0 ]; }
searches() { grep -c '^api search' "$fake_log"; }
asked() { grep '^api search' "$fake_log" | tr '\n' '|'; }
titles() { dekho_state | jq -c '[.search.results[] | .title]'; }
heard() { grep -q "^api search $1\$" "$fake_log"; }

exec_line=$(sed -n 's/^Exec=//p' "$entry")
niri msg action spawn -- sh -c "exec $exec_line >>'$log' 2>&1"
until_ok 5000 dekho_up
until_ok 3000 dekho_is '(.rows.continue | length) == 5 and (.rows.series | length) == 10 and (.rows.movies | length) == 10'
# The first key into a new window can be lost, so a harmless one goes first.
wtype -k Shift_L
wtype /
until_ok 1000 dekho_is '.search.focused'

# One character is not a search; the count is read after the timer would have fired.
: >"$fake_log"
wtype t
sleep 0.6
check "one character sends no search ($(asked))" test "$(searches)" = 0
check "and the home rows stay ($(dekho_state | jq -c '[.rows.shown, .search.text]'))" dekho_is '.rows.shown and .search.text == "t"'

# A second character, and a pause, search without Enter.
wtype id
until_ok 3000 dekho_is '(.search.results | length) == 3'
check "tid, paused on, shows search-tide's titles ($(titles))" \
  dekho_is '[.search.results[] | .title] == ["The Long Tide", "Low Tide Radio", "Tide Tables"]'
check "while the field keeps focus and its text ($(dekho_state | jq -c '[.search.focused, .search.text, .rows.shown]'))" \
  dekho_is '.search.focused and .search.text == "tid" and (.rows.shown | not)'
check "the fake heard one search, for tid ($(asked))" test "$(asked)" = 'api search tid|'

# Deleting back to one character brings the home rows back.
wtype -k BackSpace -k BackSpace
until_ok 3000 dekho_is '.rows.shown and (.search.results | length) == 0'
check "deleting to one character brings back the home rows ($(dekho_state | jq -c '[.rows.shown, .search.text, .search.focused]'))" \
  dekho_is '.rows.shown and .search.text == "t" and .search.focused and (.search.results | length) == 0'
wtype -k BackSpace

# Four keys 80 ms apart are one search, for the whole word.
: >"$fake_log"
wtype -d 80 tide
until_ok 3000 dekho_is '(.search.results | length) == 3'
sleep 0.4
check "tide typed 80 ms apart sends one search, for tide ($(asked))" test "$(asked)" = 'api search tide|'
wtype -k Escape
until_ok 1000 dekho_is '.rows.shown and (.search.results | length) == 0'
check "Esc clears the field and the results, as before ($(dekho_state | jq -c '[.rows.shown, .search.text]'))" \
  dekho_is '.rows.shown and .search.text == "" and (.search.results | length) == 0'

# An older answer that lands late never replaces the newer one. tidx is slow and finds the harbour fixture; one BackSpace later tid finds search-tide at once.
: >"$fake_log"
echo tidx >"$DOTS_DEV_DIR/dekho-slow-search"
wtype /
until_ok 1000 dekho_is '.search.focused'
wtype tidx
until_ok 3000 heard tidx
wtype -k BackSpace
until_ok 3000 dekho_is '[.search.results[] | .title] == ["The Long Tide", "Low Tide Radio", "Tide Tables"]'
sleep 2
check "tid's results stay after tidx's late answer ($(titles))" \
  dekho_is '[.search.results[] | .title] == ["The Long Tide", "Low Tide Radio", "Tide Tables"] and .search.text == "tid"'
check "and both were asked ($(asked))" test "$(asked)" = 'api search tidx|api search tid|'

# Dropping below 2 characters drops an answer still on its way.
wtype -k BackSpace -k BackSpace -k BackSpace
until_ok 1000 dekho_is '.search.text == "" and .rows.shown'
: >"$fake_log"
echo tid >"$DOTS_DEV_DIR/dekho-slow-search"
wtype tid
until_ok 3000 heard tid
wtype -k BackSpace -k BackSpace
until_ok 1000 dekho_is '.rows.shown and .search.text == "t"'
sleep 2
check "an answer in flight when the text drops to one character never draws ($(dekho_state | jq -c '[.rows.shown, .search.text]') $(titles))" \
  dekho_is '.rows.shown and (.search.results | length) == 0 and .search.text == "t"'
rm -f "$DOTS_DEV_DIR/dekho-slow-search"

# Enter searches at once and moves the cursor to the results.
wtype -k BackSpace
: >"$fake_log"
wtype tide
wtype -k Return
until_ok 3000 dekho_is '(.search.results | length) == 3'
check "Enter searches and moves the cursor to the results ($(dekho_state | jq -c '[.focus, .search.focused]'))" \
  dekho_is '.focus == {"row": "results", "col": 0} and (.search.focused | not) and .search.text == "tide"'
sleep 0.5
check "and the search for tide went out once ($(asked))" test "$(asked)" = 'api search tide|'
wtype -k Escape
until_ok 1000 dekho_is '.rows.shown and .search.text == ""'
check "Esc leaves the results for the home rows" dekho_is '.rows.shown and .search.text == "" and (.search.results | length) == 0'

wtype -k Escape
until_ok 3000 dekho_gone
check "Esc closes the window" dekho_gone

errs=$(grep -E 'TypeError|ReferenceError|SyntaxError|Failed to load|is not a type|Cannot assign|Unable to assign|Cannot read propert|unavailable' "$log")
check "Dekho's log has no QML errors${errs:+: $(head -c 200 <<<"$errs")}" test -z "$errs"

exit $((fails > 0))
}
