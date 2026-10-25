#!/usr/bin/env bash
# Dekho's Person page by mouse: a click on a credit opens its title and leaves the cursor there, so Enter next opens it again; the wheel scrolls the credits without moving the cursor and stops at their ends.
{
source "$(dirname "$0")/lib.sh"
source "$(dirname "$0")/dekho-pointer.bash"

person_loaded() { dekho_is '.page == "person" and .personPage.ready'; }
shown() { dekho_state | jq -c '[.personPage.lines[] | select(.head | not) | .shown]'; }

open_dekho
until_ok 3000 dekho_is '(.rows.series | length) == 10'
# The Long Tide, then the crew: Mara Lindqvist, its director.
click_on series:1
until_ok 3000 dekho_is '.page == "title" and .title.season > 0'
wtype -k Tab
until_ok 1000 dekho_is '.title.zone == "crew"'
wtype -k Return
until_ok 3000 person_loaded
check "her page opens with the cursor on her first credit ($(dekho_state | jq -c '[.personPage.name, .personPage.cursor]'))" \
  dekho_is '.personPage.name == "Mara Lindqvist" and .personPage.cursor == 0'

click_on person-credit:6
until_ok 2000 dekho_is '.page == "title" and .opened == 102'
check "a click on her writing credit opens Night Ferry ($(dekho_state | jq -c '[.page, .opened]'))" dekho_is '.page == "title" and .opened == 102'
wtype -k Escape
until_ok 1000 person_loaded
check "back on her page, the cursor sits on the credit clicked ($(dekho_state | jq -c '[.personPage.cursor, .personPage.group]'))" \
  dekho_is '.personPage.cursor == 6 and .personPage.group == "writing"'
wtype -k Return
until_ok 2000 dekho_is '.page == "title" and .opened == 102'
check "so Enter opens Night Ferry again ($(dekho_state | jq -c '[.page, .opened]'))" dekho_is '.page == "title" and .opened == 102'
wtype -k Escape
until_ok 1000 person_loaded

# Her eight credits fit the window, so it is made short enough that they do not.
niri msg action set-window-height --id "$(dekho_id)" 420
until_ok 2000 dekho_is '.personPage.lines[-1].shown == false'
check "in a short window her last credits are out of view ($(shown))" dekho_is '.personPage.lines[1].shown and (.personPage.lines[-1].shown | not)'
click_on person-credit:1
until_ok 2000 dekho_is '.page == "title"'
wtype -k Escape
until_ok 1000 dekho_is '.page == "person" and .personPage.cursor == 1'
wheel_on person-credit:2 3
until_ok 1000 dekho_is '(.personPage.lines[1].shown | not)'
check "three notches down bring her first credit out of view ($(shown))" dekho_is '(.personPage.lines[1].shown | not)'
check "and leave the cursor where it was ($(dekho_state | jq -c .personPage.cursor))" dekho_is '.personPage.cursor == 1'
wheel_on person-credit:5 30
until_ok 1000 dekho_is '.personPage.lines[-1].shown'
check "thirty more stop with the last credit whole at the list's end ($(shown))" \
  dekho_is '.personPage.lines[-1].shown and (.personPage.lines[1].shown | not) and .personPage.cursor == 1'
wheel_on person-credit:7 -30
until_ok 1000 dekho_is '.personPage.lines[1].shown'
check "thirty up bring the first back ($(shown))" dekho_is '.personPage.lines[1].shown and (.personPage.lines[-1].shown | not)'

exit "$fails"
}
