#!/usr/bin/env bash
# Mod+I's calendar card: 560 px, home first, then UTC, London and New York as drawn, and an offset change taken on the next minute tick.
{
repo=$(cd "$(dirname "$0")/../.." && pwd)
# The shell runs the dots-zones beside it, so the nested shell runs a copy whose bin/ holds a wrapper around the real one.
copy=$(mktemp -d)
cp -a "$repo/shell" "$copy/shell"
for f in "$repo"/*; do [ "${f##*/}" = shell ] || [ "${f##*/}" = bin ] || ln -s "$f" "$copy/"; done
mkdir "$copy/bin"
for f in "$repo"/bin/*; do ln -s "$f" "$copy/bin/"; done
rm "$copy/bin/dots-zones"
# The first answer is the real one, its next change a second away; the second moves London back an hour, as its October change does.
cat >"$copy/bin/dots-zones" <<EOF
#!/usr/bin/env bash
n=\$((\$(cat "$copy/calls" 2>/dev/null || echo 0) + 1))
echo "\$n" >"$copy/calls"
if [ "\$n" = 1 ]; then
  "$repo/bin/dots-zones" | jq -c '.next = (now | floor) + 1'
else
  "$repo/bin/dots-zones" | jq -c '(.zones[] | select(.id == "Europe/London") | .offset) -= 3600 | .next = null'
fi
EOF
chmod +x "$copy/bin/dots-zones"
export DOTS_DEV_SHELL=$copy/shell
source "$(dirname "$0")/lib.sh"
cleanup() { rm -rf "$copy"; }

island() { timeout 0.5 qs ipc call island state 2>/dev/null; }
mode_is() { island | jq -e --arg m "$1" '.mode == $m' >/dev/null 2>&1; }
calls() { cat "$copy/calls" 2>/dev/null || echo 0; }
# A zone's offset in seconds east of UTC, now or an hour ago.
secs() { local z; z=$(TZ=$1 date ${2:+-d "$2"} +%z); echo $((${z:0:1}1 * (10#${z:1:2} * 3600 + 10#${z:3:2} * 60))); }
# As the card writes it: a true minus, whole hours, and :mm only when there are minutes.
offset_text() {
  local s=$1 sign=+ m
  ((s == 0)) && { echo 0h; return; }
  ((s < 0)) && { sign=−; s=$((-s)); }
  m=$((s / 60 % 60))
  if ((m)); then printf '%s%d:%02dh\n' "$sign" $((s / 3600)) "$m"; else printf '%s%dh\n' "$sign" $((s / 3600)); fi
}
day_word() {
  local d h
  d=$(TZ=$1 date ${2:+-d "$2"} +%F) h=$(date +%F)
  if [[ $d > $h ]]; then echo tomorrow; elif [[ $d < $h ]]; then echo yesterday; else echo; fi
}
home=$(readlink /etc/localtime)
home=${home#*zoneinfo/}
home_city=${home##*/}
home_city=${home_city//_/ }

check "dots-zones has not run before the calendar first opens ($(calls) calls)" test "$(calls)" = 0

niri msg action spawn -- dots-call island focus
loaded() { island | jq -e '.mode == "calendar" and (.calendar.cities | length) == 4 and .animating == false' >/dev/null 2>&1; }
until_ok 4000 loaded
# The times are read twice around the state, so a minute that turns during the read still matches one of them.
before=$(date +%s)
state=$(island)
after=$(date +%s)
echo "     calendar: $(jq -c '{width, drawn, cities: .calendar.cities}' <<<"$state")"
wide() { jq -e '(.width | type) == "number" and .width == 560 and .drawn == 560' <<<"$state" >/dev/null; }
check "the calendar card is 560 px wide, as drawn" wide

# row <index> <zone> <utc-shift>: the drawn row names the zone's city, its time and day at either read, and its offset from home.
row() {
  local i=$1 id=$2 shift=${3:-} city=${2##*/} t1 t2 off want_off
  city=${city//_/ }
  t1=$(TZ=$id date -d "@$((before + ${shift:-0}))" +%H:%M)
  t2=$(TZ=$id date -d "@$((after + ${shift:-0}))" +%H:%M)
  off=$(($(secs "$id") + ${shift:-0} - $(secs "$home")))
  want_off=$([ "$i" = 0 ] || offset_text "$off")
  jq -e --argjson i "$i" --arg city "$city" --arg t1 "$t1" --arg t2 "$t2" --arg off "$want_off" --arg day "$(day_word "$id" "@$((before + ${shift:-0}))")" '
    .calendar.cities[$i] as $r
    | ($r.city | ascii_downcase) == ($city | ascii_downcase)
      and ($r.time == $t1 or $r.time == $t2)
      and ($r.offset | ascii_downcase) == ($off | ascii_downcase)
      and ($r.day | ascii_downcase) == $day' <<<"$state" >/dev/null
}
check "home, $home_city, is the first row with its time and no offset" row 0 "$home"
check "UTC is drawn with its time and offset from home" row 1 UTC
check "London is drawn with its time and offset from home" row 2 Europe/London
check "New York is drawn with its time and offset from home" row 3 America/New_York
check "the calendar's first open ran dots-zones once ($(calls))" test "$(calls)" = 1

# The first answer's next change is a second away, so the next minute tick reruns dots-zones and London's offset moves an hour.
moved() { island | jq -e --arg off "$(offset_text $(($(secs Europe/London) - 3600 - $(secs "$home"))))" '(.calendar.cities[2].offset | ascii_downcase) == ($off | ascii_downcase)' >/dev/null 2>&1; }
until_ok 70000 moved
before=$(date +%s)
state=$(island)
after=$(date +%s)
echo "     after the change: $(jq -c '.calendar.cities[2]' <<<"$state")"
check "after the change London is drawn an hour back, without a restart" row 2 Europe/London -3600
check "and dots-zones ran just once more ($(calls))" test "$(calls)" = 2

wtype -k Escape
until_ok 1000 mode_is rest
niri msg action spawn -- dots-call island focus
until_ok 4000 loaded
check "opening the calendar again runs no dots-zones ($(calls))" test "$(calls)" = 2

# Each theme puts the offset and day word elsewhere (beside, under or right of the city), and each must draw them.
rows() { island | jq -c '[.calendar.cities[] | {city, offset, day} | map_values(ascii_downcase)]'; }
want=$(rows)
status_theme() { shell_status | jq -e --arg t "$1" '.theme == $t' >/dev/null; }
same_rows() { [ "$(rows)" = "$want" ]; }
for t in paper artboard blueprint; do
  wtype -k Escape
  until_ok 1000 mode_is rest
  "$repo/bin/dots" theme "$t" >/dev/null
  until_ok 2000 status_theme "$t"
  niri msg action spawn -- dots-call island focus
  until_ok 4000 loaded
  echo "     $t: $(rows)"
  check "$t draws every city's offset and day word" same_rows
done

exit $((fails > 0))
}
