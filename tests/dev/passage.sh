#!/usr/bin/env bash
# The daily passage on the real deen and its texts: the date override over the four kinds, each kind's lines as drawn, each theme's design and a switch between them, back to today, read through passage state.
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

# A second date set while deen still reads the first ends on the second day's own text, never the first's.
dots-call passage date 2026-11-11 && dots-call passage date 2026-11-07
until_ok 3000 passage_is '.date == "2026-11-07" and .en != ""'
check "two ayah days set inside one deen call end on 2026-11-07's own ayah, 2:152 ($(passage | jq -c '[.date, .ref, .en[0:30]]'))" \
  passage_is '.date == "2026-11-07" and .ref == "Al-Baqara 2:152" and (.en | startswith("So remember Me"))'

on_day 2026-11-04
check "2026-11-04 is the first hadith, bukhari:1, in English only ($(passage | jq -c '[.kind, .entry, .ref, .ar]'))" \
  passage_is '.kind == "hadith" and .entry == 0 and (.ref | startswith("Sahih al-Bukhari 1 · ")) and .ar == "" and (.en | startswith("Narrated") | not)'

on_day 2026-11-01
check "2026-11-01 is the 30th dua, Hisn al-Muslim 235 ($(passage | jq -c '[.kind, .entry, .ref]'))" passage_is '.kind == "dua" and .entry == 29 and .ref == "Hisn al-Muslim 235" and .ar != ""'

on_day 2026-11-02
check "2026-11-02 is quote 89, Picasso's ($(passage | jq -c '[.kind, .entry, .en, .ref]'))" \
  passage_is '.kind == "quote" and .entry == 89 and .en == "Action is the foundational key to all success." and .ref == "Pablo Picasso"'

# What the paper on screen draws, from its sheet's own Text items.
drawn() { passage | jq -c ".drawn[0][0] | ${1:-.}"; }
drawn_is() { passage | jq -e --arg arabic "$arabic" "(.drawn | length) == 1 and (.drawn[0] | length) == 1 and (.drawn[0][0] | $1)" >/dev/null 2>&1; }
on_drawn() { dots-call passage date "$1" && until_ok 3000 drawn_is "$2"; }
status_theme() { shell_status | jq -e --arg t "$1" '.theme == $t and .transition == ""' >/dev/null; }
in_theme() { "$repo/bin/dots" theme "$1" >/dev/null; until_ok 3000 status_theme "$1"; }
# A theme switch is done when the sheet it left draws nothing.
switched() { in_theme "$1" && until_ok 3000 drawn_is "$2"; }
arabic=Amiri
fc-list : family | grep -qx Amiri || arabic="Noto Naskh Arabic"
# Saved for Saiful to set beside the boards, when the run names a folder.
shot() { [ -z "${DOTS_PASSAGE_SHOTS:-}" ] || grim -o "$(niri msg -j outputs | jq -r 'keys[0]')" "$DOTS_PASSAGE_SHOTS/$1.png"; }

in_theme paper
on_drawn 2026-11-03 '.ref == "Ash-Sharh 94:6"'
check "Paper draws 94:6's Arabic in $arabic over its English in Instrument Serif ($(drawn '[.family.ar, .family.en, .ar != "", .en]'))" \
  drawn_is '.family.ar == $arabic and .family.en == "Instrument Serif" and .ar != "" and .en == "Indeed, with hardship [will be] ease."'
check "Paper's label is AYAH in Maple Mono ($(passage | jq -c '[.label, .drawn[0][0].label, .drawn[0][0].family.label]'))" \
  passage_is '.label == "AYAH" and .drawn[0][0].label == "AYAH" and .drawn[0][0].family.label == "Maple Mono" and .ref == "Ash-Sharh 94:6"'
out=$(niri msg -j outputs | jq -c 'first(.[]).logical')
centred() { passage | jq -e --argjson o "$out" '.drawn[0][0].box | ((.x + .w / 2) - ($o.width / 2) | fabs) < 2 and ((.y + .h / 2) - ($o.height / 2) | fabs) < 2' >/dev/null; }
check "the block sits centred on the output ($(drawn .box), output $out)" centred
shot paper

switched blueprint '.label == "[AYAH]"'
check "Blueprint labels it [AYAH] and its reference ASH-SHARH 94:6 ($(passage | jq -c '[.label, .ref, .drawn[0][0].ref]'))" \
  passage_is '.label == "[AYAH]" and .ref == "ASH-SHARH 94:6" and .drawn[0][0].ref == "ASH-SHARH 94:6"'
check "after the switch settles one sheet draws the passage ($(passage | jq -c '.drawn | map(length)'))" drawn_is '.label == "[AYAH]"'
check "Blueprint's English is Maple Mono ($(drawn .family.en))" drawn_is '.family.en == "Maple Mono"'
shot blueprint

switched artboard '.label == "Ayah"'
check "Artboard labels it Ayah over the card, its reference as deen names it ($(passage | jq -c '[.label, .ref]'))" passage_is '.label == "Ayah" and .ref == "Ash-Sharh 94:6"'
check "after the switch settles one sheet draws the passage ($(passage | jq -c '.drawn | map(length)'))" drawn_is '.label == "Ayah"'
shot artboard

in_theme paper
on_drawn 2026-12-14 '.ref | startswith("Sahih al-Bukhari 6114")'
check "bukhari:6114 draws English from Allah's Messenger on, no Arabic, Abu Huraira in its reference ($(drawn '[.ar, .en[0:40], .ref]'))" \
  drawn_is '.ar == "" and (.en | startswith("Allah'"'"'s Messenger (ﷺ) said")) and .ref == "Sahih al-Bukhari 6114 · Abu Huraira"'
on_drawn 2027-01-23 '.ref == "Sahih Muslim 6602"'
check "muslim:6602 draws as given, a space after saying:, no narrator in its reference ($(drawn '[.en[0:90], .ref]'))" \
  drawn_is '(.en | startswith("A'"'"'isha, the wife of Allah'"'"'s Apostle (ﷺ), reported Allah'"'"'s Apostle (ﷺ) as saying: Kindness is not")) and .ref == "Sahih Muslim 6602"'
on_drawn 2026-11-08 '.ref | startswith("Sahih al-Bukhari 6013")'
check "bukhari:6013 gains its closing quote ($(drawn '.en[-20:]'))" drawn_is '.en | endswith("mercifully\"")'
on_drawn 2026-11-21 '.ref == "Hisn al-Muslim 16"'
check "dua 16 draws its Arabic in $arabic over its English ($(drawn '[.family.ar, .en]'))" \
  drawn_is '.family.ar == $arabic and .ar != "" and .en == "In the Name of Allah, I have placed my trust in Allah, there is no might and no power except by Allah."'
shot dua-16
on_drawn 2026-12-24 '.ref == "Walt Disney"'
check "Walt Disney's quote draws its sentence over his name ($(drawn '[.en, .ar]'))" drawn_is '.en == "The best way to get started is to quit talking and begin doing." and .ar == ""'
on_drawn 2027-01-09 '.ref == "Henry Ford"'
check "Henry Ford's quote splits at its last dash ($(drawn .en))" drawn_is '.en == "Whether you think you can, or you think you can'"'"'t — you'"'"'re right."'

on_day 2026-11-02
dots-call passage date 2026-02-30
check "a date that is no day is refused, and the quote stays" passage_is '.date == "2026-11-02"'

dots-call passage date ""
until_ok 3000 passage_is --arg d "$today" '.date == $d and .en != ""'
check "an empty date returns to today, $today ($(passage | jq -r .date))" passage_is --arg d "$today" '.date == $d and .en != ""'

exit $((fails > 0))
}
