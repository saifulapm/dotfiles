#!/usr/bin/env bash
# Dekho's Browse by mouse: a click on a result row opens its title and leaves the cursor there; a click on a kind tab or a facet does what its key does; a click on a person in p's picker adds them, and a click on the picker never reaches the rows under it; the wheel scrolls the results without moving the cursor and stops at both ends.
{
source "$(dirname "$0")/lib.sh"
source "$(dirname "$0")/dekho-pointer.bash"

calls=$DOTS_DEV_DIR/dekho.log
cursor() { dekho_state | jq -c .browse.cursor; }
chips() { dekho_state | jq -c '[.browse.chips[].text]'; }
shown() { dekho_state | jq -c "[.browse.rows[$1] | .shown]"; }
asked_since() { tail -n +"$(($1 + 1))" "$calls" | grep '^api discover '; }
asked() { asked_since "$mark" | sort | tr '\n' ';'; }
# Click a named area and wait for the discover calls it makes, and for the rows to be drawn.
tap() {
  mark=$(wc -l <"$calls")
  click_on "$1"
  until_ok 3000 bash -c "[ \$(tail -n +$((mark + 1)) '$calls' | grep -c '^api discover ') -ge $2 ]"
  until_ok 3000 dekho_is '(.browse.rows | length) > 0'
}
# Each facet click asks what its key asks and reads the chips its key reads.
facet() {
  tap "browse-facet:$1" 1
  check "a click on the $1 facet asks $(asked)" test "$(asked)" = "$2"
  check "  and the chips read $3 ($(chips))" test "$(chips)" = "$3"
}

open_dekho
until_ok 3000 dekho_is '(.rows.series | length) == 10'
wtype f
until_ok 3000 dekho_is '.page == "browse" and (.browse.rows | length) == 34'
check "f on Home opens Browse with the fake's 34 titles ($(dekho_state | jq -c '[.page, (.browse.rows | length)]'))" \
  dekho_is '.page == "browse" and (.browse.rows | length) == 34 and .browse.cursor == 0'

click_on browse-row:3
until_ok 2000 dekho_is '.page == "title" and .opened == 101'
check "a click on the fourth row opens The Long Tide's title ($(dekho_state | jq -c '[.page, .opened]'))" dekho_is '.page == "title" and .opened == 101'
wtype -k Escape
until_ok 1000 dekho_is '.page == "browse"'
check "back on Browse, the cursor sits on the row clicked ($(cursor))" dekho_is '.browse.cursor == 3 and .browse.rows[3].cursor'
wtype -k Return
until_ok 2000 dekho_is '.page == "title" and .opened == 101'
check "so Enter opens the same title again ($(dekho_state | jq -c '[.page, .opened]'))" dekho_is '.page == "title" and .opened == 101'
wtype -k Escape
until_ok 1000 dekho_is '.page == "browse"'

# The wheel: 34 rows of 44 or 46 px in a window that shows fewer than 20.
wheel_on browse-row:5 3
until_ok 1000 dekho_is '(.browse.rows[1].shown | not)'
check "three notches down over the results bring the second row out of view ($(shown 1))" \
  dekho_is '(.browse.rows[0].shown | not) and (.browse.rows[1].shown | not)'
check "and leave the cursor where it was ($(cursor))" dekho_is '.browse.cursor == 3'
wheel_on browse-row:20 40
until_ok 1000 dekho_is '.browse.rows[33].shown'
check "forty more stop with the last row whole at the end ($(shown 33))" dekho_is '.browse.rows[33].shown and .browse.cursor == 3'
wheel_on browse-row:20 5
check "and five more do not move it ($(shown 33))" dekho_is '.browse.rows[33].shown and (.browse.rows[0].shown | not) and .browse.cursor == 3'
wheel_on browse-row:20 -80
until_ok 1000 dekho_is '.browse.rows[0].shown'
check "eighty up bring the first row back whole ($(shown 0))" dekho_is '.browse.rows[0].shown and .browse.cursor == 3'

# The kind tabs and the facets, each as its key does, from nothing chosen.
tap browse-kind:tv 1
check "a click on the Series tab asks series only ($(asked))" test "$(asked)" = 'api discover --kind tv;'
check "  and the chips read Series ($(chips))" test "$(chips)" = '["Series"]'
check "and the tab reads current ($(dekho_state | jq -c '[.browse.kinds[].current]'))" dekho_is '[.browse.kinds[].current] == [false, false, true]'
facet sort 'api discover --kind tv --sort top-rated;' '["Series"]'
facet genre 'api discover --kind tv --sort top-rated --genre 10759;' '["Series","Action & Adventure"]'
facet language 'api discover --kind tv --sort top-rated --genre 10759 --lang hi;' '["Series","Action & Adventure","Hindi"]'
facet decade 'api discover --kind tv --sort top-rated --genre 10759 --lang hi --year 1970-1979;' '["Series","Action & Adventure","Hindi","1970s"]'
facet rating 'api discover --kind tv --sort top-rated --genre 10759 --lang hi --year 1970-1979 --min-rating 6;' '["Series","Action & Adventure","Hindi","1970s","★ 6+"]'
wtype x
until_ok 3000 dekho_is '(.browse.rows | length) == 34'
tap browse-kind:movie 1
check "a click on the Movies tab, after x, asks films only ($(asked))" test "$(asked)" = 'api discover --kind movie;'
check "  and the chips read Movies ($(chips))" test "$(chips)" = '["Movies"]'
tap browse-kind:all 2
check "a click on the All tab asks both kinds ($(asked))" test "$(asked)" = 'api discover --kind movie;api discover --kind tv;'
check "  and the chips are empty ($(chips))" test "$(chips)" = '[]'

# A click while the rows load: a facet change empties the rows at once and the fake answers a moment later. Both clicks go to the pointer together, the second on the first row's place, which holds no row until the answer lands.
at=$(spot browse-row:0)
fat=$(spot browse-facet:sort)
n=$(done_count click)
echo "click $fat" >&7
echo "click $at" >&7
until_ok 15000 done_more click $((n + 1))
# The fake answers within the 50 ms a click holds, so the second click may land on the new first row, Harbour Lights (300); the old first row, A Quiet Verdict (400), is never opened.
until_ok 3000 dekho_is '(.browse.rows | length) == 34'
check "a click on the first row's place opens nothing of the old rows ($(dekho_state | jq -c '[.page, .opened]'))" dekho_is '.page == "browse" or .opened == 300'
if dekho_is '.page == "title"'; then
  wtype -k Escape
  until_ok 1000 dekho_is '.page == "browse"'
fi

# p's picker, opened by a click on the person facet.
click_on browse-facet:person
until_ok 1000 dekho_is '.browse.picker.open'
check "a click on the person facet opens the picker as p does ($(dekho_state | jq -c '.browse.facets[5]'))" \
  dekho_is '.browse.picker.open and .browse.facets[5].value == "typing…" and .browse.facets[5].open'
wtype mara
until_ok 3000 dekho_is '(.browse.picker.people | length) == 2'

# A click in the picker's 6 px margin beside its second person, where the first result rows lie under it, opens nothing and leaves the picker open.
read -r px py <<<"$(spot browse-person:1 0)"
point click $((px - 3)) "$py"
check "a click on the picker's body opens no title through it ($(dekho_state | jq -c '[.page, .browse.picker.open]'))" \
  dekho_is '.page == "browse" and .browse.picker.open'
wheel_on browse-person:0 3
check "and the wheel over it does not scroll the results beneath ($(shown 0))" dekho_is '.browse.rows[0].shown'

mark=$(wc -l <"$calls")
click_on browse-person:1
until_ok 3000 bash -c "[ \$(tail -n +$((mark + 1)) '$calls' | grep -c '^api discover ') -ge 2 ]"
until_ok 3000 dekho_is '.browse.picker.open == false and (.browse.rows | length) > 0'
check "a click on the second person asks for her films and series ($(asked))" test "$(asked)" = 'api discover --kind movie --sort top-rated --person 1002;api discover --kind tv --sort top-rated --person 1002;'
check "  and the chips read Mara Okoye, the picker closed ($(chips))" test "$(chips)" = '["Mara Okoye"]'

errs=$(grep -E 'TypeError|ReferenceError|SyntaxError|Failed to load|is not a type|Cannot assign|Unable to assign|Cannot read propert|unavailable|Binding loop' "$log")
check "Dekho's log has no QML errors${errs:+: $(head -c 200 <<<"$errs")}" test -z "$errs"

exit "$fails"
}
