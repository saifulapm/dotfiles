#!/usr/bin/env bash
# The daily passage on the real deen and its texts: the date override over the four kinds, back to today, read through passage state.
{
# The shell asks the real deen, on the texts dots apply put in place, since the nested data dir holds none.
texts=$HOME/.local/share/deen
work=$(mktemp -d)
printf '#!/bin/sh\nDEEN_DATA=%q DEEN_WORDS=%q DEEN_DUAS=%q DEEN_HADITH=%q exec %q "$@"\n' \
  "$texts/quran.json" "$texts/words.json" "$texts/duas.json" "$texts/hadith" "$(command -v deen)" >"$work/deen"
chmod +x "$work/deen"
export DOTS_DEV_DEEN=$work/deen
source "$(dirname "$0")/lib.sh"
cleanup() { rm -rf "$work"; }

passage() { timeout 0.5 dots-call passage state 2>/dev/null; }
passage_is() { passage | jq -e "$@" >/dev/null 2>&1; }
on_day() { dots-call passage date "$1" && until_ok 3000 passage_is --arg d "$1" '.date == $d and .en != ""'; }

until_ok 5000 shell_status >/dev/null
until_ok 5000 passage_is '.en != ""'
today=$(date +%F)
check "with no date set the passage is today's, $today ($(passage | jq -c '[.date, .kind, .ref]'))" passage_is --arg d "$today" '.date == $d and .fallback == false'

on_day 2026-11-03
check "2026-11-03 is the first ayah, 94:6 ($(passage | jq -c '[.kind, .entry, .ref]'))" passage_is '.kind == "ayah" and .entry == 0 and .ref == "Ash-Sharh 94:6" and .day == 20760'
# deen spells shadda before fatha, so the Arabic is checked against its own answer, not a typed copy.
ar=$("$work/deen" api ayah 94:6 | jq -r .ayah.ar)
check "its Arabic and English are deen's ($(passage | jq -c '[.ar, .en]'))" passage_is --arg ar "$ar" '.ar == $ar and .en == "Indeed, with hardship [will be] ease."'

on_day 2026-11-04
check "2026-11-04 is the first hadith, bukhari:1, in English only ($(passage | jq -c '[.kind, .entry, .ref, .ar]'))" \
  passage_is '.kind == "hadith" and .entry == 0 and (.ref | startswith("Sahih al-Bukhari 1 · ")) and .ar == "" and (.en | startswith("Narrated") | not)'

on_day 2026-11-01
check "2026-11-01 is the 30th dua, Hisn al-Muslim 235 ($(passage | jq -c '[.kind, .entry, .ref]'))" passage_is '.kind == "dua" and .entry == 29 and .ref == "Hisn al-Muslim 235" and .ar != ""'

on_day 2026-11-02
check "2026-11-02 is quote 89, Picasso's ($(passage | jq -c '[.kind, .entry, .en, .ref]'))" \
  passage_is '.kind == "quote" and .entry == 89 and .en == "Action is the foundational key to all success." and .ref == "Pablo Picasso"'

dots-call passage date 2026-02-30
check "a date that is no day is refused, and the quote stays" passage_is '.date == "2026-11-02"'

dots-call passage date ""
until_ok 3000 passage_is --arg d "$today" '.date == $d and .en != ""'
check "an empty date returns to today, $today ($(passage | jq -r .date))" passage_is --arg d "$today" '.date == $d and .en != ""'

exit $((fails > 0))
}
