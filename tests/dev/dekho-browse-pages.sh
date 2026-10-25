#!/usr/bin/env bash
# Dekho's Browse pages: the cursor on the last row loads the next page under the rows, once however often j is pressed, until the last page, where no load more row shows and nothing more is asked; Enter or a click on load more does the same; a filter change starts again at page 1 and drops a page still on its way; each board's look of the load more row.
{
source "$(dirname "$0")/lib.sh"
source "$(dirname "$0")/dekho-pointer.bash"

calls=$DOTS_DEV_DIR/dekho.log
# Every discover answers 3 pages of 20 made-up hits, "Film 2-07" the seventh film of page 2.
echo 3 >"$DOTS_DEV_DIR/dekho-many-pages"
cleanup() {
  rm -f "$DOTS_DEV_DIR/dekho-many-pages" "$DOTS_DEV_DIR/dekho-slow-pages" "$DOTS_DEV_DIR/dekho-pages-fail"
  pointer_stop
}

status_theme() { shell_status | jq -e --arg t "$1" '.theme == $t and .transition == ""' >/dev/null; }
in_theme() { "$repo/bin/dots" theme "$1" >/dev/null; until_ok 3000 status_theme "$1"; }
rows() { dekho_state | jq -c '.browse | [(.rows | length), .cursor, .more.shown, .loading]'; }
# The discover calls since the log had $1 lines; the checks run their conditions in bash -c, which needs it.
asked_since() { tail -n +"$(($1 + 1))" "$calls" | grep '^api discover '; }
asked() { asked_since "$mark" | sort | tr '\n' ';'; }
export -f asked_since
export calls
# n presses of j, in one wtype.
js() { wtype "$(printf 'j%.0s' $(seq "$1"))"; }

open_dekho
until_ok 3000 dekho_is '(.rows.series | length) == 10'
wtype f
until_ok 3000 dekho_is '.page == "browse" and (.browse.rows | length) == 40'
check "f opens Browse on both kinds' first pages, 20 each, with load more under them ($(rows))" \
  dekho_is '(.browse.rows | length) == 40 and .browse.more.shown'
mark=$(wc -l <"$calls")
wtype t
until_ok 3000 dekho_is '(.browse.rows | length) == 20 and .browse.rows[0].title == "Film 1-01"'
check "Movies only: page 1 draws 20 rows and a load more row reading ↵ LOAD MORE in Paper ($(rows), $(dekho_state | jq -c .browse.more))" \
  dekho_is '(.browse.rows | length) == 20 and .browse.more.shown and .browse.more.text == "↵ LOAD MORE" and (.browse.more.cursor | not)'
check "  asked as page 1 is, with no --page ($(asked))" test "$(asked)" = 'api discover --kind movie;'

# The auto load: nothing before the last row, one page 2 on it.
mark=$(wc -l <"$calls")
js 18
until_ok 2000 dekho_is '.browse.cursor == 18'
check "the cursor on row 19 of 20 asks no page yet ($(rows), $(asked))" test -z "$(asked)"
wtype j
until_ok 3000 dekho_is '(.browse.rows | length) == 40'
check "the cursor on row 20 asks movies' page 2 once ($(asked))" test "$(asked)" = 'api discover --kind movie --page 2;'
check "  and the list draws 40 rows, page 2's under page 1's, with the cursor still on row 20 ($(rows), $(dekho_state | jq -c '[.browse.rows[19,20].title]'))" \
  dekho_is '(.browse.rows | length) == 40 and .browse.cursor == 19 and .browse.rows[19].cursor and .browse.rows[19].title == "Film 1-20" and .browse.rows[20].title == "Film 2-01" and .browse.rows[39].title == "Film 2-20"'

# A page on its way: j at the end again asks it no second time.
echo 2 >"$DOTS_DEV_DIR/dekho-slow-pages"
mark=$(wc -l <"$calls")
js 20
until_ok 2000 dekho_is '.browse.cursor == 39 and .browse.loading'
wtype jjj
until_ok 1000 dekho_is '.browse.cursor == 40'
check "j past the last row while page 3 is on its way stands on load more ($(rows))" dekho_is '.browse.cursor == 40 and .browse.more.cursor and (.browse.rows | length) == 40'
# Enter on load more, then k and j back onto the last row, each would ask page 3 again.
wtype -k Return
wtype kj
until_ok 1000 dekho_is '.browse.cursor == 40'
until_ok 4000 dekho_is '(.browse.rows | length) == 60'
rm -f "$DOTS_DEV_DIR/dekho-slow-pages"
check "  and page 3 was asked once for j, j again, Enter on load more, and k j back to the last row ($(asked))" test "$(asked)" = 'api discover --kind movie --page 3;'
check "page 3 draws 60 rows and no load more row, the cursor on page 3's first ($(rows))" \
  dekho_is '(.browse.rows | length) == 60 and (.browse.more.shown | not) and .browse.cursor == 40 and .browse.rows[40].title == "Film 3-01"'
mark=$(wc -l <"$calls")
js 25
until_ok 2000 dekho_is '.browse.cursor == 59'
sleep 0.5
check "on the last page, the cursor on the last row asks nothing more ($(rows), $(asked))" \
  bash -c "[ -z \"\$(tail -n +$((mark + 1)) '$calls' | grep '^api discover ')\" ] && dekho_is '.browse.cursor == 59 and .browse.rows[59].cursor'"

# A filter change starts again at page 1.
mark=$(wc -l <"$calls")
wtype g
until_ok 3000 dekho_is '(.browse.rows | length) == 20 and .browse.filters.genre != null'
check "g after page 3 asks page 1 again, no --page ($(asked)), and draws 20 rows and load more ($(rows))" \
  bash -c "[ \"\$(asked_since $mark | tr '\n' ';')\" = 'api discover --kind movie --genre 28;' ] && dekho_is '(.browse.rows | length) == 20 and .browse.more.shown and .browse.cursor == 0'"

# Enter on load more: a failed page 2 leaves load more to try again.
touch "$DOTS_DEV_DIR/dekho-pages-fail"
mark=$(wc -l <"$calls")
js 19
until_ok 3000 bash -c "[ \"\$(tail -n +$((mark + 1)) '$calls' | grep -c '^api discover ')\" = 1 ] && dekho_is '.browse.loading | not'"
wtype j
until_ok 1000 dekho_is '.browse.cursor == 20'
check "a failed page 2 ($(asked)) keeps 20 rows and load more, j standing on it ($(rows))" \
  bash -c "[ \"\$(asked_since $mark | tr '\n' ';')\" = 'api discover --kind movie --genre 28 --page 2;' ] && dekho_is '(.browse.rows | length) == 20 and .browse.more.shown and .browse.more.cursor'"
rm -f "$DOTS_DEV_DIR/dekho-pages-fail"
wtype -k Return
until_ok 3000 dekho_is '(.browse.rows | length) == 40'
check "Enter on load more asks page 2 again ($(asked)) and draws 40 rows ($(rows))" \
  bash -c "[ \"\$(asked_since $mark | tr '\n' ';')\" = 'api discover --kind movie --genre 28 --page 2;api discover --kind movie --genre 28 --page 2;' ] && dekho_is '(.browse.rows | length) == 40 and .page == \"browse\"'"

# A click on load more, scrolled into view.
wheel_on browse-row:20 40
until_ok 1000 dekho_is '.browse.more.inView'
mark=$(wc -l <"$calls")
click_on browse-more
until_ok 3000 dekho_is '(.browse.rows | length) == 60'
check "a click on load more asks page 3 once ($(asked)) and draws 60 rows ($(rows))" \
  bash -c "[ \"\$(asked_since $mark | tr '\n' ';')\" = 'api discover --kind movie --genre 28 --page 3;' ] && dekho_is '(.browse.rows | length) == 60 and .page == \"browse\" and (.browse.more.shown | not)'"

# Both kinds page together.
wtype x
until_ok 3000 dekho_is '(.browse.rows | length) == 40 and .browse.filters.kind == "all"'
mark=$(wc -l <"$calls")
js 39
until_ok 3000 dekho_is '(.browse.rows | length) == 80'
check "with kind All, the last row asks each kind's page 2 once ($(asked))" test "$(asked)" = 'api discover --kind movie --page 2;api discover --kind tv --page 2;'
check "  and draws 80 rows, the two pages alternating under page 1 ($(dekho_state | jq -c '[.browse.rows[39,40,41].title]'))" \
  dekho_is '(.browse.rows | length) == 80 and .browse.cursor == 39 and [.browse.rows[38,39,40,41,79].title] == ["Film 1-20", "Series 1-20", "Film 2-01", "Series 2-01", "Series 2-20"]'

# A page on its way when a filter changes never lands under the new rows.
echo 2 >"$DOTS_DEV_DIR/dekho-slow-pages"
mark=$(wc -l <"$calls")
js 40
until_ok 2000 dekho_is '.browse.cursor == 79 and .browse.loading'
wtype d
until_ok 3000 dekho_is '(.browse.rows | length) == 40 and .browse.filters.decade == 1970'
sleep 2.5
rm -f "$DOTS_DEV_DIR/dekho-slow-pages"
check "d while both page 3s are on their way asks both kinds' page 1 ($(asked))" \
  test "$(asked)" = 'api discover --kind movie --page 3;api discover --kind movie --year 1970-1979;api discover --kind tv --page 3;api discover --kind tv --year 1970-1979;'
check "  and the late page 3s are dropped: 40 rows of page 1 only ($(rows), $(dekho_state | jq -c '[.browse.rows[].title | .[-4:-3]] | unique'))" \
  dekho_is '(.browse.rows | length) == 40 and ([.browse.rows[].title | test(" 1-")] | all) and (.browse.loading | not) and .browse.more.shown'

# Each board's look of load more.
in_theme artboard
until_ok 3000 dekho_is '.voice == "plain"'
check "artboard: load more reads ↵ load more ($(dekho_state | jq -c .browse.more))" dekho_is '.browse.more.text == "↵ load more"'
in_theme blueprint
until_ok 3000 dekho_is '.voice == "bracket"'
check "blueprint: load more reads [↵] LOAD MORE ($(dekho_state | jq -c .browse.more))" dekho_is '.browse.more.text == "[↵] LOAD MORE"'
in_theme paper
until_ok 3000 dekho_is '.voice == "caps"'

errs=$(grep -E 'TypeError|ReferenceError|SyntaxError|Failed to load|is not a type|Cannot assign|Unable to assign|Cannot read propert|unavailable|Binding loop' "$log")
check "Dekho's log has no QML errors${errs:+: $(head -c 200 <<<"$errs")}" test -z "$errs"

exit "$fails"
}
