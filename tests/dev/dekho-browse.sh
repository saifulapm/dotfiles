#!/usr/bin/env bash
# f opens Dekho's Browse from Home empty and from a Title page with its kind, genre and language as chips; each facet key asks the fake for its filter and the rows redraw from its answer; x clears; each board's look.
{
source "$(dirname "$0")/lib.sh"

dekho_qml=$repo/shell/dekho.qml
entry=$repo/home/dot_local/share/applications/dekho.desktop
work=$(mktemp -d)
cleanup() { rm -rf "$work"; }
log=$work/dekho.log
calls=$DOTS_DEV_DIR/dekho.log

dekho_state() { timeout 0.5 qs ipc -p "$dekho_qml" call dekho state 2>/dev/null; }
dekho_is() { dekho_state | jq -e "$@" >/dev/null 2>&1; }
dekho_windows() { niri msg -j windows | jq '[.[] | select(.app_id == "dekho")] | length'; }
dekho_up() { [ "$(dekho_windows)" = 1 ] && dekho_is '.firstFrameMs != null'; }
dekho_gone() { [ "$(dekho_windows)" = 0 ]; }
status_theme() { shell_status | jq -e --arg t "$1" '.theme == $t and .transition == ""' >/dev/null; }
in_theme() { "$repo/bin/dots" theme "$1" >/dev/null; until_ok 3000 status_theme "$1"; }
title_loaded() { dekho_is '.page == "title" and .title.season > 0 and (.title.episodes | length) > 0'; }
chips() { dekho_state | jq -c '[.browse.chips[].text]'; }
titles() { dekho_state | jq -c '[.browse.rows[].title]'; }

# The discover calls the App made since the log had $1 lines.
asked_since() { tail -n +"$(($1 + 1))" "$calls" | grep '^api discover '; }
# What the fake answers those calls, each title one-lined as the App draws it; the fake runs against a scratch log so the App's own stays whole.
answer_for() {
  local args
  while read -r args; do
    # shellcheck disable=SC2086
    DOTS_DEV_DIR=$work "$repo/bin/dev-fake-dekho" $args
  done | node --input-type=module -e '
    import { readFileSync } from "node:fs";
    const { oneLine } = await import(process.argv[1]);
    const lines = readFileSync(0, "utf8").split("\n").filter((l) => l);
    console.log(JSON.stringify(lines.map((l) => JSON.parse(l).items.map((h) => oneLine(h.title)))));
  ' "$repo/shell/lib/picker.mjs"
}
# One call's rows drawn in the fake's order; two calls' rows are both answers' titles, in the order the sort merges them.
drawn_matches() {
  local answers
  answers=$(asked_since "$1" | answer_for)
  [ -n "$answers" ] && titles | jq -e --argjson a "$answers" 'if ($a | length) == 1 then . == $a[0] else sort == ($a | add | sort) end' >/dev/null
}
# Press a key and wait for the rows to be the fake's answer to the calls it made.
press() {
  mark=$(wc -l <"$calls")
  before=$(titles)
  wtype "$1"
  until_ok 3000 bash -c "[ \$(tail -n +$((mark + 1)) '$calls' | grep -c '^api discover ') -ge $2 ]"
  until_ok 3000 drawn_matches "$mark"
}
asked() { asked_since "$mark" | tr '\n' ';'; }
# The checks run their conditions in bash -c, which needs these.
export -f asked_since answer_for drawn_matches dekho_state titles chips
export calls work repo dekho_qml

no_code() { dekho_is '[.browse.chips[].text, (.browse.rows[] | .title, .year, .rating)] | all(test("^[a-z]{2}$") or test("^[A-Z]{2}$") | not)'; }

exec_line=$(sed -n 's/^Exec=//p' "$entry")
niri msg action spawn -- sh -c "exec $exec_line >>'$log' 2>&1"
until_ok 5000 dekho_up
until_ok 3000 dekho_is '(.rows.series | length) == 10'

# From Home: nothing chosen, both kinds by popularity.
mark=$(wc -l <"$calls")
wtype f
until_ok 3000 dekho_is '.page == "browse" and (.browse.rows | length) == 27'
check "f on Home opens Browse with no chip and nothing prefilled ($(dekho_state | jq -c '.browse | [.chips, .from, .prefilled]'))" \
  dekho_is '.page == "browse" and .browse.chips == [] and .browse.prefilled == "" and .browse.from == "from home"'
check "it asks both kinds unfiltered ($(asked)) and draws all 27, a movie then a series ($(titles | jq -c '.[0:4]'))" \
  bash -c "asked_since $mark | sort | tr '\n' ';' | grep -qx 'api discover --kind movie;api discover --kind tv;' && [ \"\$(titles | jq -c '.[0:4]')\" = '[\"A Quiet Verdict\",\"Harbour Lights\",\"Seven Stations\",\"The Long Tide\"]' ]"
check "a title with a newline, U+202E and ESC draws on one line without them ($(dekho_state | jq -c '[.browse.rows[] | select(.title | test("Radio"))][0]'))" \
  dekho_is '[.browse.rows[] | select(.title | test("Radio"))][0] | .title == "Low Tide Radio" and .lines == 1'
check "the 308-character title draws on one elided line ($(dekho_state | jq -c '[.browse.rows[] | select(.title | test("^The Very")) | {lines, elided}]'))" \
  dekho_is '[.browse.rows[] | select(.title | test("^The Very"))][0] | .lines == 1 and .elided'
check "the summary reads All · Popular and the count 27 titles ($(dekho_state | jq -c '[.browse.summary, .browse.count]'))" \
  dekho_is '.browse.summary == "All · Popular" and .browse.count == "27 titles"'
wtype -k Escape
until_ok 1000 dekho_is '.page == "home"'
check "esc on Browse goes back to Home ($(dekho_state | jq -c .page))" dekho_is '.page == "home" and .focus.row != "search"'

# From The Long Tide's page: its kind, first genre and language.
wtype jl
until_ok 1000 dekho_is '.focus == {"row": "series", "col": 1}'
wtype -k Return
until_ok 3000 title_loaded
mark=$(wc -l <"$calls")
wtype f
until_ok 3000 dekho_is '.page == "browse" and (.browse.rows | length) > 0'
check "f on The Long Tide opens Browse with Series, Drama and English as chips ($(chips))" \
  dekho_is '[.browse.chips[].text] == ["Series", "Drama", "English"] and all(.browse.chips[]; .lines == 1)'
check "and keeps the title's filter in state ($(dekho_state | jq -c .filter))" dekho_is '.filter == {"kind": "tv", "genre": "Drama", "language": "English"}'
check "it asks for series in Drama, English ($(asked)) and draws the fake's answer ($(titles | jq -c '.[0:3]'))" \
  bash -c "[ \"\$(asked_since $mark)\" = 'api discover --kind tv --genre 18 --lang en' ] && drawn_matches $mark"
check "each row draws its language and genres, as the board's last two columns ($(dekho_state | jq -c '.browse.rows[0] | [.title, .language, .genres]'))" \
  dekho_is '.browse.rows[0] | .language == "English" and .genres == "Drama · Mystery"'
check "the header reads where it came from and the chips are marked prefilled ($(dekho_state | jq -c '.browse | [.from, .prefilled]'))" \
  dekho_is '.browse.from == "from The Long Tide" and .browse.prefilled == "PREFILLED FROM THE LONG TIDE"'
check "the facets read Popular, Drama, English and Any for the rest, and the kind tab Series ($(dekho_state | jq -c '[.browse.facets[] | .value]'))" \
  dekho_is '[.browse.facets[] | .value] == ["Popular", "Drama", "English", "Any", "Any", "Any"] and .browse.kinds == [{"text": "All", "current": false}, {"text": "Movies", "current": false}, {"text": "SERIES", "current": true}]'
check "no chip or row reads a two-letter code" no_code

step() {
  local key=$1 n=$2 want=$3 chips_want=$4
  press "$key" "$n"
  check "$key asks $(asked) and the rows redraw from the fake's answer ($(titles | jq -c '.[0:3]'), was $(jq -c '.[0:3]' <<<"$before"))" \
    bash -c "[ \"\$(asked_since $mark | sort | tr '\n' ';')\" = '$want' ] && drawn_matches $mark && [ '$before' != \"\$(titles)\" ] && [ \"\$(titles)\" != '[]' ]"
  check "  and the chips read $chips_want ($(chips))" bash -c "[ \"\$(chips)\" = '$chips_want' ]"
}
step s 1 'api discover --kind tv --sort top-rated --genre 18 --lang en;' '["Series","Drama","English"]'
check "s reads Top rated in its box and the summary ($(dekho_state | jq -c '[.browse.facets[0].value, .browse.summary]'))" \
  dekho_is '.browse.facets[0].value == "Top rated" and .browse.summary == "Series · Top rated · Drama · English"'
step g 1 'api discover --kind tv --sort top-rated --genre 10751 --lang en;' '["Series","Family","English"]'
step l 1 'api discover --kind tv --sort top-rated --genre 10751 --lang sv;' '["Series","Family","Swedish"]'
step d 1 'api discover --kind tv --sort top-rated --genre 10751 --lang sv --year 1970-1979;' '["Series","Family","Swedish","1970s"]'
step r 1 'api discover --kind tv --sort top-rated --genre 10751 --lang sv --year 1970-1979 --min-rating 6;' '["Series","Family","Swedish","1970s","★ 6+"]'
step t 2 'api discover --kind movie --sort top-rated --genre 10751 --lang sv --year 1970-1979 --min-rating 6;api discover --kind tv --sort top-rated --genre 10751 --lang sv --year 1970-1979 --min-rating 6;' '["Family","Swedish","1970s","★ 6+"]'
check "t on Series wraps to All, a series and a film drawn by rating ($(titles))" dekho_is '[.browse.rows[].title] == ["Midsummer Ward", "Summer Island"]'

# p: a person found by name, Enter adds them.
wtype p
until_ok 1000 dekho_is '.browse.picker.open'
check "p opens the person picker, its box reading typing… ($(dekho_state | jq -c '.browse.facets[5]'))" dekho_is '.browse.picker.open and .browse.facets[5].value == "typing…" and .browse.facets[5].open'
wtype mara
until_ok 3000 dekho_is '(.browse.picker.people | length) == 2'
check "typing mara lists the fake's two people, one-lined, with what each is known for ($(dekho_state | jq -c '[.browse.picker.people[] | [.name, .role, .lines]]'))" \
  dekho_is '[.browse.picker.people[] | [.name, .role, .lines]] == [["Mara Lindqvist", "director", 1], ["Mara Okoye", "actor", 1]] and .browse.picker.people[0].cursor'
check "the fake heard the name" grep -qx 'api people mara' "$calls"
mark=$(wc -l <"$calls")
before=$(titles)
wtype -k Return
until_ok 3000 bash -c "[ \$(tail -n +$((mark + 1)) '$calls' | grep -c '^api discover ') -ge 2 ]"
until_ok 3000 drawn_matches "$mark"
check "Enter adds Mara Lindqvist ($(asked)) and the rows redraw from the fake's answer ($(titles), was $before)" \
  bash -c "[ \"\$(asked_since $mark | sort | tr '\n' ';')\" = 'api discover --kind movie --sort top-rated --genre 10751 --lang sv --year 1970-1979 --min-rating 6 --person 1001;api discover --kind tv --sort top-rated --genre 10751 --lang sv --year 1970-1979 --min-rating 6 --person 1001;' ] && drawn_matches $mark && [ \"\$(titles)\" = '[\"Summer Island\"]' ]"
check "  the picker closes, the page stays Browse and the chips end with her name ($(chips))" \
  dekho_is '.browse.picker.open == false and .page == "browse" and [.browse.chips[].text] == ["Family", "Swedish", "1970s", "★ 6+", "Mara Lindqvist"]'
check "no chip or row reads a two-letter code" no_code

mark=$(wc -l <"$calls")
wtype x
until_ok 3000 dekho_is '(.browse.rows | length) == 27'
check "x clears every chip and the prefilled mark ($(chips))" dekho_is '.browse.chips == [] and .browse.prefilled == "" and .browse.summary == "All · Popular"'
check "and the rows are the unfiltered set again ($(asked); $(titles | jq -c '.[0:4]'))" \
  bash -c "[ \"\$(asked_since $mark | sort | tr '\n' ';')\" = 'api discover --kind movie;api discover --kind tv;' ] && drawn_matches $mark && [ \"\$(titles | jq -c '.[0:4]')\" = '[\"A Quiet Verdict\",\"Harbour Lights\",\"Seven Stations\",\"The Long Tide\"]' ]"

wtype -k Escape
until_ok 1000 dekho_is '.page == "title"'
check "esc on Browse goes back to the Title page it came from ($(dekho_state | jq -c '[.page, .title.name]'))" dekho_is '.page == "title" and .title.name == "The Long Tide"'

# Each board's own detail, on Browse from The Long Tide.
wtype f
until_ok 3000 dekho_is '.page == "browse" and (.browse.chips | length) == 3 and (.browse.rows | length) > 0'
check "paper: Browse is set in Instrument Serif and the chips filled #F3E6CF, as the Paper board draws them ($(dekho_state | jq -c '.browse.look'))" \
  dekho_is '.browse.look.pageFont == "Instrument Serif" and (.browse.look.chipFill | ascii_downcase) == "#f3e6cf" and .browse.look.chipRadius == 0'
in_theme artboard
until_ok 3000 dekho_is '.voice == "plain"'
check "artboard: chips are rounded 13 px on #EEF1FF and kind tabs 10 px, as the Artboard board draws them ($(dekho_state | jq -c '.browse.look'))" \
  dekho_is '.browse.look.chipRadius == 13 and (.browse.look.chipFill | ascii_downcase) == "#eef1ff" and .browse.look.kindRadius == 10 and .browse.prefilled == "prefilled from The Long Tide" and .browse.kinds[2].text == "Series"'
in_theme blueprint
until_ok 3000 dekho_is '.voice == "bracket"'
check "blueprint: the header and the prefilled mark are capitals in brackets, kinds in capitals, rules dashed, as the Blueprint board writes them ($(dekho_state | jq -c '.browse | [.from, .prefilled, [.kinds[].text], .look.ruleDashed]'))" \
  dekho_is '.browse.from == "FROM THE LONG TIDE" and .browse.prefilled == "[PREFILLED FROM THE LONG TIDE]" and [.browse.kinds[].text] == ["ALL", "MOVIES", "SERIES"] and .browse.look.ruleDashed and .browse.count == "9 TITLES"'
in_theme paper
until_ok 3000 dekho_is '.voice == "caps"'

wtype -k Escape
until_ok 1000 dekho_is '.page == "title"'
wtype -k Escape
until_ok 1000 dekho_is '.page == "home"'
wtype -k Escape
until_ok 3000 dekho_gone
check "esc on Browse, Title, then Home closes the window" dekho_gone

errs=$(grep -E 'TypeError|ReferenceError|SyntaxError|Failed to load|is not a type|Cannot assign|Unable to assign|Cannot read propert|unavailable|Binding loop' "$log")
check "Dekho's log has no QML errors${errs:+: $(head -c 200 <<<"$errs")}" test -z "$errs"

exit $((fails > 0))
}
