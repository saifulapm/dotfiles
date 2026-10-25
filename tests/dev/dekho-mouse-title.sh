#!/usr/bin/env bash
# Dekho's Title page by mouse: a click on an episode, a season tab, a person, a button or a chip moves the cursor there and does what Enter does, and the wheel scrolls the episode list without moving the cursor.
{
# Play, Resume and Trailer start units on this machine's real user manager, so this run's units get a name of their own, set before lib.sh starts the session that inherits it.
export DOTS_DEKHO_UNIT=dekho-mouse-title-test-$$
source "$(dirname "$0")/lib.sh"
source "$(dirname "$0")/dekho-pointer.bash"

runtime=${XDG_RUNTIME_DIR:-/tmp}/dekho
sessions=$work/sessions
cleanup() {
  systemctl --user stop "$DOTS_DEKHO_UNIT.service" "$DOTS_DEKHO_UNIT-trailer.service" 2>/dev/null
  [ -f "$sessions" ] && xargs -r rm -f <"$sessions"
  rm -f "$runtime/$DOTS_DEKHO_UNIT.log" "$runtime/$DOTS_DEKHO_UNIT.session" "$runtime/$DOTS_DEKHO_UNIT-trailer.log" "$runtime/$DOTS_DEKHO_UNIT-trailer.session"
  pointer_stop
}
fake_log=$DOTS_DEV_DIR/dekho.log

title_loaded() { dekho_is '.page == "title" and .title.season > 0 and (.title.episodes | length) > 0'; }
cursor() { dekho_state | jq -c '.title | [.zone, .season, .cursor]'; }
shown() { dekho_state | jq -c '[.title.episodes[].shown]'; }
# The index of the first, or with "last" the last, episode row drawn whole, for the wheel to turn over.
shown_at() { dekho_state | jq -r "[.title.episodes | to_entries[] | select(.value.shown) | .key] | ${1:-first}"; }
lines() { grep -c "$1" "$fake_log"; }
unit_active() { systemctl --user is-active --quiet "$DOTS_DEKHO_UNIT.service"; }
unit_inactive() { ! unit_active; }
trailer_active() { systemctl --user is-active --quiet "$DOTS_DEKHO_UNIT-trailer.service"; }
note_session() { dekho_state | jq -r '.releases.session, .trailer.session' >>"$sessions"; }
dekho_focused() { niri msg -j focused-window | jq -e '.app_id == "dekho"' >/dev/null; }
# niri focuses the window mpv maps, so the keys after it go back to Dekho by hand, with a key first to hand it niri's keymap.
refocus() {
  niri msg action focus-window --id "$(dekho_id)"
  until_ok 1000 dekho_focused
  wtype -k Shift_L
}

open_dekho
until_ok 3000 dekho_is '(.rows.series | length) == 10'
# The Long Tide is the second trending series: it opens on S3, the cursor on E4, next up; E5 airs in a week.
click_on series:1
until_ok 3000 title_loaded
until_ok 3000 dekho_is '.title.tmdbId == 101 and .title.season == 3 and .title.cursor == 4'
check "a click on The Long Tide opens its Title page on S3 E4 ($(cursor))" dekho_is '.title.name == "The Long Tide" and .title.cursor == 4'

click_on title-episode:4
until_ok 1000 dekho_is '.title.cursor == 5'
check "a click on E5, not aired yet, moves the cursor there and opens nothing ($(dekho_state | jq -c '[.title.cursor, .releases.mode, .chose]'))" \
  dekho_is '.title.zone == "episodes" and .title.cursor == 5 and .releases.mode == "" and .chose == null'

click_on title-episode:1
until_ok 3000 dekho_is '.releases.mode == "list" and (.releases.rows | length) == 6'
check "a click on E2 opens its release list, the cursor on E2 ($(dekho_state | jq -c '[.releases.heading, .chose, .title.cursor]'))" \
  dekho_is '.releases.mode == "list" and (.releases.heading | startswith("The Long Tide · S3 E2")) and .chose == {"season": 3, "episode": 2} and .title.cursor == 2'
wtype -k Escape
until_ok 1000 dekho_is '.page == "title" and .releases.mode == ""'
check "esc closes it, back on the Title page ($(dekho_state | jq -c '[.page, .releases.mode]'))" dekho_is '.page == "title" and .releases.mode == ""'
wtype -k Return
until_ok 3000 dekho_is '.releases.mode == "list" and (.releases.rows | length) == 6'
check "so Enter opens the same release list again ($(dekho_state | jq -c '[.releases.heading, .chose]'))" \
  dekho_is '.releases.mode == "list" and (.releases.heading | startswith("The Long Tide · S3 E2")) and .chose == {"season": 3, "episode": 2}'
wtype -k Escape
until_ok 1000 dekho_is '.releases.mode == ""'

# The window is cut to 810 px so a season's eight 30 px rows are longer than the list's view.
dekho_tall() { niri msg -j windows | jq -e --argjson h "$1" '.[] | select(.app_id == "dekho") | .layout.window_size[1] == $h' >/dev/null; }
niri msg action set-window-height --id "$(dekho_id)" 810
until_ok 2000 dekho_tall 810
dekho_at=$(dekho_origin)
until_ok 1000 dekho_is '.title.episodes[7].shown == false'
check "in an 810 px window S3's list holds its first four rows and not its last ($(shown))" \
  dekho_is '[.title.episodes[0:4][].shown] == [true, true, true, true] and .title.episodes[7].shown == false'

click_on title-season:0
until_ok 1000 dekho_is '.title.season == 1'
check "a click on the S1 tab shows S1's episodes, all watched ($(dekho_state | jq -c '[.title.season, .title.zone, .title.count, .title.tabs[0].current]'))" \
  dekho_is '.title.season == 1 and .title.zone == "episodes" and .title.tabs[0].current and .title.count == "8 of 8 watched" and (.title.episodes | length) == 8'
click_on title-season:2
until_ok 1000 dekho_is '.title.season == 3'
check "a click on the S3 tab shows S3's again, the cursor on E4, next up ($(cursor) $(dekho_state | jq -c .title.count))" \
  dekho_is '.title.season == 3 and .title.cursor == 4 and .title.count == "3 of 8 watched"'

until_ok 1000 dekho_is '.title.episodes[0].shown'
check "S3's list starts at its first row, its last out of view ($(shown))" dekho_is '.title.episodes[0].shown and .title.episodes[7].shown == false'
wheel_on "title-episode:$(shown_at)" 3
until_ok 1000 dekho_is '.title.episodes[0].shown == false'
check "three notches down over the episodes bring the first row out of view ($(shown))" dekho_is '.title.episodes[0].shown == false'
check "and leave the cursor where it was ($(cursor))" dekho_is '.title.zone == "episodes" and .title.cursor == 4'
wheel_on "title-episode:$(shown_at)" 30
until_ok 1000 dekho_is '.title.episodes[7].shown'
check "thirty more stop with the last row in view ($(shown))" dekho_is '.title.episodes[7].shown and .title.episodes[0].shown == false'
wheel_on "title-episode:$(shown_at last)" -30
until_ok 1000 dekho_is '.title.episodes[0].shown'
check "thirty up bring the first row back ($(shown))" dekho_is '.title.episodes[0].shown and .title.episodes[7].shown == false and .title.cursor == 4'

click_on title-crew:0
until_ok 2000 dekho_is '.page == "person"'
check "a click on the director's chip opens Mara Lindqvist ($(dekho_state | jq -c '[.page, .person]'))" dekho_is '.page == "person" and .person == 1001'
wtype -k Escape
until_ok 1000 dekho_is '.page == "title"'
check "esc back leaves the cursor on that chip ($(dekho_state | jq -c '[.title.zone, [.title.crew[].focused]]'))" \
  dekho_is '.title.zone == "crew" and [.title.crew[].focused] == [true, false, false]'
click_on title-cast:1
until_ok 2000 dekho_is '.page == "person"'
check "a click on the second cast chip opens Omar Reyes ($(dekho_state | jq -c '[.page, .person]'))" dekho_is '.page == "person" and .person == 2002'
wtype -k Escape
until_ok 1000 dekho_is '.page == "title"'
check "esc back leaves the cursor on that chip ($(dekho_state | jq -c '[.title.zone, [.title.cast[].focused]]'))" \
  dekho_is '.title.zone == "cast" and [.title.cast[].focused] == [false, true, false]'

check "the chips read the genres, then the language ($(dekho_state | jq -c '[.title.chips[].text]'))" dekho_is '[.title.chips[].text] == ["Drama", "Mystery", "English"]'
click_on title-genre:1
until_ok 3000 dekho_is '.page == "browse" and (.browse.chips | length) > 0'
check "a click on the Mystery chip opens Browse with that one genre ($(dekho_state | jq -c '[.page, [.browse.chips[].text]]'))" \
  dekho_is '.page == "browse" and [.browse.chips[].text] == ["Mystery"]'
wtype -k Escape
until_ok 1000 dekho_is '.page == "title"'
click_on title-language
until_ok 3000 dekho_is '.page == "browse" and (.browse.chips | length) > 0'
check "a click on the English chip opens Browse with that one language ($(dekho_state | jq -c '[.page, [.browse.chips[].text]]'))" \
  dekho_is '.page == "browse" and [.browse.chips[].text] == ["English"]'
wtype -k Escape
until_ok 1000 dekho_is '.page == "title"'

# Two clicks on Play with no wait between: one ask for releases, and no run.
asks=$(lines '^api releases --id 101 --kind tv -s 3 -e 4$')
runs=$(lines '^play ')
at=$(spot title-button:play)
# shellcheck disable=SC2086
point click $at
# shellcheck disable=SC2086
point click $at
until_ok 3000 dekho_is '.releases.mode == "list" and (.releases.rows | length) == 6'
sleep 1
check "two fast clicks on Play open one release list for E4, the cursor's episode ($(dekho_state | jq -c '[.releases.mode, .releases.heading]'), $(($(lines '^api releases --id 101 --kind tv -s 3 -e 4$') - asks)) asks)" \
  bash -c "timeout 0.5 qs ipc -p '$dekho_qml' call dekho state | jq -e '.releases.mode == \"list\" and .title.zone == \"buttons\" and .title.buttons[0].focused and .chose == {\"season\": 3, \"episode\": 4}' >/dev/null && [ \$(grep -c '^api releases --id 101 --kind tv -s 3 -e 4\$' '$fake_log') = $((asks + 1)) ]"
check "and start no run ($(($(lines '^play ') - runs)) plays)" test "$(lines '^play ')" = "$runs"
wtype -k Escape
until_ok 1000 dekho_is '.releases.mode == ""'

trailers=$(lines '^trailer --json --id 101 --kind tv$')
click_on title-button:trailer
until_ok 3000 trailer_active
note_session
check "a click on Trailer starts the trailer as t does ($(($(lines '^trailer --json --id 101 --kind tv$') - trailers)) asks)" \
  bash -c "systemctl --user is-active --quiet '$DOTS_DEKHO_UNIT-trailer.service' && [ \$(grep -c '^trailer --json --id 101 --kind tv\$' '$fake_log') = $((trailers + 1)) ]"
check "with the cursor on it ($(dekho_state | jq -c '[.title.zone, [.title.buttons[].focused]]'))" dekho_is '.title.zone == "buttons" and .title.buttons[-1].focused'
# The trailer's mpv window took the focus: the first click back on Dekho acts at once, with no click first to focus it. mpv floats over Dekho, so it moves off it first.
until_ok 3000 bash -c "niri msg -j focused-window | jq -e '.app_id == \"mpv\"' >/dev/null"
niri msg action move-floating-window --id "$(niri msg -j focused-window | jq .id)" -x 1300 -y 700
until_ok 2000 bash -c "niri msg -j focused-window | jq -e '.app_id == \"mpv\" and .layout.tile_pos_in_workspace_view[0] >= 1300' >/dev/null"
click_on title-episode:1
until_ok 3000 dekho_is '.releases.mode == "list" and (.releases.rows | length) == 6'
check "with mpv focused, one click on E2 opens its release list ($(dekho_state | jq -c '[.releases.mode, .chose]'))" \
  dekho_is '.releases.mode == "list" and .chose == {"season": 3, "episode": 2}'
wtype -k Shift_L
wtype -k Escape
until_ok 1000 dekho_is '.releases.mode == ""'
"$repo/bin/dots-dekho-play" --trailer --stop
refocus

# History holds The Long Tide unfinished at S3 E4, so Resume is drawn.
until_ok 3000 dekho_is '[.title.buttons[].kind] == ["play", "resume", "trailer"]'
click_on title-button:resume
until_ok 3000 unit_active
note_session
check "a click on Resume plays where history stopped, with no list, as r does ($(dekho_state | jq -c '[.releases.mode, .chose]'))" \
  bash -c "grep -qx 'play --json --id 101 --kind tv --resume' '$fake_log' && timeout 0.5 qs ipc -p '$dekho_qml' call dekho state | jq -e '.chose == {\"resume\": true} and .title.buttons[1].focused and .releases.mode != \"list\"' >/dev/null"
until_ok 8000 dekho_is '.releases.mode == ""'
systemctl --user stop "$DOTS_DEKHO_UNIT.service" 2>/dev/null
until_ok 3000 unit_inactive
refocus

errs=$(grep -E 'TypeError|ReferenceError|SyntaxError|Failed to load|is not a type|Cannot assign|Unable to assign|Cannot read propert|unavailable|Binding loop' "$log")
check "Dekho's log has no QML errors${errs:+: $(head -c 200 <<<"$errs")}" test -z "$errs"

exit "$fails"
}
