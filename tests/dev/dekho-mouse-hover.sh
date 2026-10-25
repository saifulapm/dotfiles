#!/usr/bin/env bash
# Hover in Dekho changes only the pointer: a pointing hand over each card, chip, row, tab and button, an arrow elsewhere, read off the drawn cursor; and the window under a pointer over a card draws the same pixels as with the pointer off it.
{
source "$(dirname "$0")/lib.sh"
source "$(dirname "$0")/dekho-pointer.bash"

# The cursor's own pixels at x y: a 48 px square there taken with the cursor and without, and the offsets where the two differ, as JSON.
sprite() {
  local g="$(($1 - 8)),$(($2 - 8)) 48x48"
  grim -c -s 1 -t ppm -g "$g" "$work/with.ppm" && grim -s 1 -t ppm -g "$g" "$work/without.ppm" || return 1
  node -e '
    const fs = require("fs");
    const read = (f) => { const b = fs.readFileSync(f); const h = b.toString("latin1").match(/^P6\s+(\d+)\s+(\d+)\s+(\d+)\s/); return b.subarray(h[0].length); };
    const a = read(process.argv[1]), b = read(process.argv[2]), out = [];
    for (let i = 0; i < a.length / 3; i++) if (Math.abs(a[i * 3] - b[i * 3]) + Math.abs(a[i * 3 + 1] - b[i * 3 + 1]) + Math.abs(a[i * 3 + 2] - b[i * 3 + 2]) > 30) out.push(i);
    console.log(JSON.stringify(out));
  ' "$work/with.ppm" "$work/without.ppm"
}
# How alike two sprites are: the share of their pixels both draw.
alike() { jq -n --argjson a "$1" --argjson b "$2" '(($a - ($a - $b)) | length) / ([$a[], $b[]] | unique | length)'; }
# The pointer moved to x y, then the sprite once it has settled, two takes in a row alike.
settled_sprite() {
  local s1 s2 _
  point move "$1" "$2"
  for _ in $(seq 1 20); do
    s1=$(sprite "$1" "$2")
    sleep 0.1
    s2=$(sprite "$1" "$2")
    [ "$s1" = "$s2" ] && [ "$s1" != "[]" ] && { echo "$s1"; return 0; }
  done
  echo "$s2"
}
at_of() { spot "$1"; }
# A spot in the window by its own pixels from the top left.
in_window() { read -r fx fy <<<"$dekho_at"; echo "$((fx + $1)) $((fy + $2))"; }
# The spot $2 px below a click area's bottom edge, at its middle.
below() { read -r fx fy <<<"$dekho_at"; dekho_box "$1" | jq -r --argjson fx "$fx" --argjson fy "$fy" --argjson d "$2" '"\(($fx + .x + .w / 2) | floor) \(($fy + .y + .h + $d) | floor)"'; }
# Over a dark or inked background part of a sprite draws no difference, so a sprite is the shape it is more alike, by a clear margin.
is_hand() { jq -ne --argjson h "$(alike "$1" "$hand")" --argjson a "$(alike "$1" "$arrow")" '$h >= $a + 0.1' >/dev/null || { echo "  $(alike "$1" "$hand") alike the hand, $(alike "$1" "$arrow") the arrow"; return 1; }; }
is_arrow() { jq -ne --argjson h "$(alike "$1" "$hand")" --argjson a "$(alike "$1" "$arrow")" '$a >= $h + 0.1' >/dev/null || { echo "  $(alike "$1" "$hand") alike the hand, $(alike "$1" "$arrow") the arrow"; return 1; }; }
hover_hand() {
  local at s
  at=$(at_of "$1") || { echo "  no click area named $1 is drawn"; return 1; }
  # shellcheck disable=SC2086
  s=$(settled_sprite $at)
  is_hand "$s"
}
hover_arrow() {
  local s
  s=$(settled_sprite "$1" "$2")
  is_arrow "$s"
}

open_dekho
until_ok 3000 dekho_is '(.rows.continue | length) == 5 and (.rows.series | length) == 10 and (.rows.movies | length) == 10'
until_ok 3000 dekho_is '[.rows.continue[], .rows.series[], .rows.movies[] | select(.poster.shown)] | length == 19'

# The two shapes compared against: Home's empty header and a trending card.
# shellcheck disable=SC2046
arrow=$(settled_sprite $(in_window 700 26))
# shellcheck disable=SC2046
hand=$(settled_sprite $(spot series:1))
check "the arrow over Home's empty header and the hand over a card are told apart ($(alike "$arrow" "$hand") alike, $(jq length <<<"$arrow") and $(jq length <<<"$hand") px)" \
  jq -ne --argjson s "$(alike "$arrow" "$hand")" --argjson a "$(jq length <<<"$arrow")" --argjson h "$(jq length <<<"$hand")" '$s < 0.6 and $a > 20 and $h > 20' >/dev/null

# Hover changes no pixel of the window: with the pointer over a card and off it, the window draws the same, cursor aside.
read -r fx fy <<<"$dekho_at"
geom="$fx,$fy 1200x716"
point move $(spot movies:2)
sleep 0.3
grim -s 1 -t ppm -g "$geom" "$work/over.ppm"
# shellcheck disable=SC2046
point move $(in_window 700 26)
sleep 0.3
grim -s 1 -t ppm -g "$geom" "$work/off.ppm"
check "the window with the pointer over a card draws the same pixels as with it off the card" cmp -s "$work/over.ppm" "$work/off.ppm"

check "a hand over a continue-watching card" hover_hand continue:0
check "a hand over a trending movie" hover_hand movies:3
# shellcheck disable=SC2046
check "an arrow between Home's rows" hover_arrow $(below continue:0 11)

# Hover over each thing a click acts on in every page, and the arrow beside them.
same_pixels() {
  point move $(spot "$1")
  sleep 0.3
  grim -s 1 -t ppm -g "$geom" "$work/over.ppm"
  point move $(in_window "$2" "$3")
  sleep 0.3
  grim -s 1 -t ppm -g "$geom" "$work/off.ppm"
  cmp -s "$work/over.ppm" "$work/off.ppm"
}

click_on series:1
until_ok 3000 dekho_is '.page == "title" and .title.season == 3 and (.title.episodes | length) > 0 and (.title.crew | length) > 0 and (.title.cast | length) > 0'
for name in title-episode:1 title-season:0 title-crew:0 title-cast:0 title-button:play title-button:trailer title-genre:0 title-language; do
  check "a hand over the title page's $name" hover_hand "$name"
done
# shellcheck disable=SC2046
check "an arrow over the title page's header" hover_arrow $(in_window 700 26)
# shellcheck disable=SC2046
check "the title page draws the same with the pointer over an episode and off it" same_pixels title-episode:1 700 26

click_on title-button:play
until_ok 3000 dekho_is '.releases.mode == "list" and (.releases.rows | length) == 6'
check "a hand over the release list's Auto row" hover_hand release:0
check "a hand over a release" hover_hand release:3
# shellcheck disable=SC2046
check "an arrow over the dimmer beside the release list" hover_arrow $(in_window 10 400)
check "the release list draws the same with the pointer over a row and off it" same_pixels release:2 10 400
wtype -k Escape
until_ok 1000 dekho_is '.releases.mode == ""'

click_on title-crew:0
until_ok 3000 dekho_is '.page == "person" and .personPage.ready'
check "a hand over a person's credit" hover_hand person-credit:1
check "the person page draws the same with the pointer over a credit and off it" same_pixels person-credit:1 700 26
wtype -k Escape
until_ok 1000 dekho_is '.page == "title"'
wtype -k Escape
until_ok 1000 dekho_is '.page == "home"'

wtype f
until_ok 3000 dekho_is '.page == "browse" and (.browse.rows | length) > 0'
for name in browse-row:2 browse-kind:movie browse-facet:genre browse-facet:sort; do
  check "a hand over Browse's $name" hover_hand "$name"
done
check "Browse draws the same with the pointer over a row and off it" same_pixels browse-row:2 700 26
wtype p
until_ok 1000 dekho_is '.browse.picker.open'
wtype mara
until_ok 3000 dekho_is '(.browse.picker.people | length) == 2'
check "a hand over a person in Browse's picker" hover_hand browse-person:0

exit "$fails"
}
