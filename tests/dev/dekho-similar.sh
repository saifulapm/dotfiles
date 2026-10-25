#!/usr/bin/env bash
# Dekho's Title page ends in MORE LIKE THIS: up to 10 similar titles as Home's cards with posters, the last Tab zone, h/l moving along it, Enter or a click opening a title that esc comes back from, and no row for a title without similar titles.
{
source "$(dirname "$0")/lib.sh"
source "$(dirname "$0")/dekho-pointer.bash"

fake_log=$DOTS_DEV_DIR/dekho.log
title_loaded() { dekho_is '.page == "title" and .title.season > 0 and (.title.episodes | length) > 0'; }
named() { dekho_is --arg n "$1" '.page == "title" and .title.name == $n and (.title.similar.cards | length) > 0'; }
film_loaded() { dekho_is '.page == "title" and .title.name == "A Quiet Verdict" and (.title.crew | length) == 3'; }
status_theme() { shell_status | jq -e --arg t "$1" '.theme == $t and .transition == ""' >/dev/null; }
in_theme() { "$repo/bin/dots" theme "$1" >/dev/null; until_ok 3000 status_theme "$1"; }
similar() { dekho_state | jq -c '.title.similar | {head, shown, cursor, top, bottom, cards: [.cards[] | [.title[0:24], .lines, .shown, .poster.shown, .poster.file]]}'; }
where() { dekho_state | jq -c '[.title.name, .title.zone, .title.similar.cursor]'; }
# Every card drawn with its w342 poster, and as many drawn on screen as the row's five columns hold.
row_drawn() {
  dekho_is --arg head "$1" '.title.similar | .shown and .head == $head and (.cards | length) == 10
    and all(.cards[]; .poster.shown and (.poster.file | test("^like101-[0-9]+\\.jpg$")) and .lines == 1)
    and ([.cards[] | select(.shown)] | length) == 5'
}
posters_asked() { grep -qx 'api prefetch --size w342 /like101-1.jpg /like101-2.jpg /like101-3.jpg /like101-4.jpg /like101-5.jpg /like101-6.jpg /like101-7.jpg /like101-8.jpg /like101-9.jpg /like101-10.jpg' "$fake_log"; }

open_dekho
until_ok 3000 dekho_is '(.rows.series | length) == 10'

# The Long Tide, the second trending series, has 12 similar titles.
click_on series:1
until_ok 3000 title_loaded
until_ok 3000 dekho_is '.title.similar.cards[0].poster.shown and .title.similar.cards[9].poster.shown'
check "The Long Tide draws MORE LIKE THIS with 10 of its 12 similar titles, each with its poster, 5 on screen ($(similar | head -c 400))" row_drawn "MORE LIKE THIS"
check "their posters came from one w342 prefetch of the 10 drawn" posters_asked
check "the series page draws its episodes, and the row below them ($(dekho_state | jq -c '[.title.episodesShown, .title.layout.episodesBottom, .title.similar.top, .title.similar.bottom]'))" \
  dekho_is '.title.episodesShown and (.title.layout.episodesBottom | type) == "number" and .title.similar.top >= .title.layout.episodesBottom and .title.similar.bottom > .title.similar.top + 60'
check "a similar title with a newline, U+202E, ESC and 300 more characters draws on one elided line without them ($(dekho_state | jq -c '.title.similar.cards[2] | {title: .title[0:40], lines, elided}'))" \
  dekho_is '.title.similar.cards[2] | .lines == 1 and .elided and (.title | startswith("Drift wood Bay [31m and the tide")) and (.title | length) > 300 and (.title | test("[\u0001-\u001f\u007f‮]") | not)'

# Tab from the buttons walks every zone, MORE LIKE THIS last, and comes back round.
wtype -k Tab
wtype -k Tab
wtype -k Tab
wtype -k Tab
until_ok 1000 dekho_is '.title.zone == "buttons"'
visited=
for _ in 1 2 3 4 5 6 7; do
  wtype -k Tab
  sleep 0.15
  visited+="$(dekho_state | jq -r .title.zone) "
done
check "tab from the buttons reaches the similar zone last, then the buttons again ($visited)" \
  test "$visited" = "links seasons episodes crew cast similar buttons "
until_ok 1000 dekho_is '.title.zone == "buttons"'
for _ in 1 2 3 4 5 6; do wtype -k Tab; done
until_ok 1000 dekho_is '.title.zone == "similar"'
check "the cursor lands on the first card ($(where))" dekho_is '.title.zone == "similar" and .title.similar.cursor == 0'
wtype l
until_ok 1000 dekho_is '.title.similar.cursor == 1'
check "l moves the cursor along the row ($(where))" dekho_is '.title.similar.cursor == 1'
wtype llll
until_ok 1000 dekho_is '.title.similar.cursor == 5'
check "the cursor on Harbour Lights, the sixth card, scrolls it on screen ($(similar | head -c 300))" \
  dekho_is '.title.similar.cursor == 5 and .title.similar.cards[5].shown and .title.similar.cards[5].title == "Harbour Lights"'

for round in 1 2; do
  wtype -k Return
  until_ok 3000 named "Harbour Lights"
  until_ok 3000 dekho_is '.title.similar.cards[2].poster.shown'
  check "round $round: Enter on Harbour Lights opens its page with its own similar row ($(dekho_state | jq -c '[.title.name, [.title.similar.cards[] | [.title, .poster.file]]]'))" \
    dekho_is '.title.name == "Harbour Lights" and .title.tmdbId == 300 and .title.similar.shown and ([.title.similar.cards[] | [.title, .poster.file]] == [["The Long Tide", "like300-1.jpg"], ["Paper Birds", "like300-2.jpg"], ["A Quiet Verdict", "like300-3.jpg"]])'
  wtype -k Escape
  until_ok 1000 dekho_is '.title.name == "The Long Tide"'
  check "round $round: esc comes back to The Long Tide in the similar zone, the cursor on Harbour Lights and its card on screen ($(where))" \
    dekho_is '.page == "title" and .title.name == "The Long Tide" and .title.tmdbId == 101 and .title.zone == "similar" and .title.similar.cursor == 5 and .title.similar.cards[5].shown and .title.similar.cards[5].title == "Harbour Lights"'
done
until_ok 3000 row_drawn "MORE LIKE THIS"
check "the row is drawn again whole ($(similar | head -c 200))" row_drawn "MORE LIKE THIS"

# Each board's own heading, on the same cards.
in_theme artboard
until_ok 3000 dekho_is '.voice == "plain"'
until_ok 3000 row_drawn "More like this"
check "artboard: the heading reads More like this over 10 cards, 5 on screen ($(similar | head -c 200))" row_drawn "More like this"
in_theme blueprint
until_ok 3000 dekho_is '.voice == "bracket"'
until_ok 3000 row_drawn "MORE LIKE THIS"
check "blueprint: the heading reads MORE LIKE THIS over 10 cards, 5 on screen ($(similar | head -c 200))" row_drawn "MORE LIKE THIS"
in_theme paper
until_ok 3000 dekho_is '.voice == "caps"'

# A click on a card opens it: A Quiet Verdict, a film with no similar titles, draws no row and Tab never stops on one.
click_on title-similar:1
until_ok 3000 film_loaded
check "a click on A Quiet Verdict's card opened its page ($(where))" dekho_is '.title.name == "A Quiet Verdict" and .title.tmdbId == 400'
check "a film with no similar titles draws no MORE LIKE THIS ($(dekho_state | jq -c '.title.similar | {shown, n: (.cards | length)}'))" \
  dekho_is '.title.similar.shown == false and (.title.similar.cards | length) == 0'
zones=
for _ in 1 2 3 4 5 6; do
  wtype -k Tab
  sleep 0.15
  zones+="$(dekho_state | jq -r .title.zone) "
done
check "tab on the film never stops on a similar zone ($zones)" bash -c "[[ '$zones' != *similar* ]] && [[ '$zones' == *buttons* ]]"
wtype -k Escape
until_ok 1000 dekho_is '.title.name == "The Long Tide"'
check "esc from the clicked film comes back to The Long Tide, the cursor on the card clicked ($(where))" \
  dekho_is '.title.name == "The Long Tide" and .title.zone == "similar" and .title.similar.cursor == 1'

errs=$(grep -E 'TypeError|ReferenceError|SyntaxError|Failed to load|is not a type|Cannot assign|Unable to assign|Cannot read propert|unavailable|Binding loop' "$log")
check "Dekho's log has no QML errors${errs:+: $(head -c 900 <<<"$errs")}" test -z "$errs"

exit "$fails"
}
