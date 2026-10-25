#!/usr/bin/env bash
# Dekho's Home by mouse: the wheel scrolls a row of titles along without moving the cursor and stops at its ends; a click on a card opens its title and leaves the cursor there, so Enter next opens it again; a click on the search field focuses it.
{
source "$(dirname "$0")/lib.sh"
source "$(dirname "$0")/dekho-pointer.bash"

focus() { dekho_state | jq -c .focus; }
shown() { dekho_state | jq -c "[.rows.$1[] | .shown]"; }

open_dekho
until_ok 3000 dekho_is '(.rows.continue | length) == 5 and (.rows.series | length) == 10 and (.rows.movies | length) == 10'
check "Dekho opens on Home with the cursor on the first title to continue ($(focus))" dekho_is '.page == "home" and .focus == {"row": "continue", "col": 0}'
check "trending series starts at its first card ($(shown series))" dekho_is '.rows.series[0].shown and (.rows.series[9].shown | not)'

wheel_on series:1 3
until_ok 1000 dekho_is '(.rows.series[0].shown | not)'
check "three notches down over trending series scroll it along, its first card out of view ($(shown series))" \
  dekho_is '(.rows.series[0].shown | not) and .rows.series[2].shown'
check "and leave the cursor where it was ($(focus))" dekho_is '.focus == {"row": "continue", "col": 0}'
check "and the rows above and below stay where they were ($(shown continue) $(shown movies))" \
  dekho_is '.rows.continue[0].shown and .rows.movies[0].shown'

wheel_on series:3 30
until_ok 1000 dekho_is '.rows.series[9].shown'
check "thirty more stop with the last card whole at the strip's end ($(shown series))" \
  dekho_is '.rows.series[9].shown and .rows.series[5].shown and (.rows.series[4].shown | not)'
wheel_on series:7 -30
until_ok 1000 dekho_is '.rows.series[0].shown'
check "thirty up bring the first card back whole ($(shown series))" dekho_is '.rows.series[0].shown and (.rows.series[9].shown | not)'

click_on series:2
until_ok 2000 dekho_is '.page == "title" and .opened == 302'
check "a click on the third trending series opens Paper Birds' title ($(dekho_state | jq -c '[.page, .opened]'))" \
  dekho_is '.page == "title" and .opened == 302'
wtype -k Escape
until_ok 1000 dekho_is '.page == "home"'
check "back on Home, the cursor sits on the card clicked ($(focus))" dekho_is '.focus == {"row": "series", "col": 2}'
wtype -k Return
until_ok 2000 dekho_is '.page == "title" and .opened == 302'
check "so Enter opens the same title again ($(dekho_state | jq -c '[.page, .opened]'))" dekho_is '.page == "title" and .opened == 302'
wtype -k Escape
until_ok 1000 dekho_is '.page == "home"'

click_on movies:4
until_ok 2000 dekho_is '.page == "title" and .opened == 404'
check "a click on a movie opens its title ($(dekho_state | jq -c '[.page, .opened]'))" dekho_is '.page == "title" and .opened == 404'
wtype -k Escape
until_ok 1000 dekho_is '.page == "home" and .focus == {"row": "movies", "col": 4}'

click_on search
until_ok 1000 dekho_is '.search.focused'
check "a click on the search field focuses it ($(dekho_state | jq -c .search))" dekho_is '.search.focused'
wtype tide
wtype -k Return
until_ok 3000 dekho_is '(.search.results | length) == 3'
click_on results:0
until_ok 2000 dekho_is '.page == "title" and .opened == 101'
check "and a click on a search result opens its title ($(dekho_state | jq -c '[.page, .opened]'))" dekho_is '.page == "title" and .opened == 101'

exit "$fails"
}
