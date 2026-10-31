#!/usr/bin/env bash
# A day deen cannot answer: deen exiting 1, a hadith corpus that is missing, an empty dua, an ayah with no Bangla; each draws a later quote in place of the day, labelled as a quote, read through passage state.
{
# The shell asks a deen that does what the mode file says: ok passes to the real deen on the texts it builds from deen-data, fail exits 1 with no output, nocorpus answers a hadith with deen's error, empty answers a dua with {}, long answers a hadith 100,000 characters long, nobn answers an ayah with its Bangla taken out, as a deen whose texts were built without deen-data does.
work=$(mktemp -d)
source "$(dirname "$0")/lib-deen-bangla.sh"
echo fail >"$work/mode"
printf '{"hit":{"collection":"muslim","bn":"সহীহ মুসলিম","name":"x","hadith":{"n":"1","bn":"%s"}}}\n' "$(head -c 100000 /dev/zero | tr '\0' x)" >"$work/long.json"
cat >"$work/deen" <<FAKE
#!/bin/sh
echo "\$*" >>$work/calls
case "\$(cat $work/mode) \$1 \$2" in
  fail*) exit 1 ;;
  "nocorpus hadith show") echo '{"error":"corpus missing"}'; exit 0 ;;
  "empty dua show") echo '{}'; exit 0 ;;
  "long hadith show") cat $work/long.json; exit 0 ;;
  "nobn api ayah") $work/deen-bangla "\$@" | jq -c 'del(.ayah.bn, .ayah.bn_pron)'; exit 0 ;;
esac
exec $work/deen-bangla "\$@"
FAKE
chmod +x "$work/deen"
export DOTS_DEV_DEEN=$work/deen
source "$(dirname "$0")/lib.sh"
cleanup() { rm -rf "$work"; }

passage() { timeout 0.5 dots-call passage state 2>/dev/null; }
passage_is() { passage | jq -e "$@" >/dev/null 2>&1; }
on_day() { dots-call passage date "$1" && until_ok 3000 passage_is --arg d "$1" '.date == $d and (.bn != "" or .en != "")'; }
mode() { echo "$1" >"$work/mode"; }
emerson='.en == "Do not go where the path may lead, go instead where there is no path and leave a trail." and .ref == "Ralph Waldo Emerson"'

until_ok 5000 shell_status >/dev/null
until_ok 5000 passage_is '.bn != "" or .en != ""'

# A deen that is not there to run, such as one dots apply has not built yet, never starts, for the surahs or the day.
mv "$work/deen" "$work/deen.gone"
on_day 2026-11-15
check "with no deen to run, ayah day 2026-11-15 falls back ($(passage | jq -c '[.fallback, .kind, .ref]'))" passage_is '.fallback == true and .kind == "ayah"'
on_day 2026-11-16
check "and so does hadith day 2026-11-16 ($(passage | jq -c '[.fallback, .kind, .ref]'))" passage_is '.fallback == true and .kind == "hadith"'
mv "$work/deen.gone" "$work/deen"

# An ayah day asks for the surahs first; a deen that never gave them is asked once for the day, not again and again.
: >"$work/calls"
on_day 2026-11-07
sleep 2
surahs=$(grep -c '^api surahs$' "$work/calls")
check "with deen exiting 1, ayah day 2026-11-07 falls back ($(passage | jq -c '[.fallback, .ref]'))" passage_is '.fallback == true and .kind == "ayah" and .ar == ""'
check "and asks deen for the surahs once, not again and again ($surahs times)" test "$surahs" = 1

mode ok
on_day 2026-11-03
check "with deen answering, 2026-11-03 draws 94:6's Arabic and Bangla ($(passage | jq -c '[.ref, .fallback, .ar != "", .bn]'))" passage_is '.ref == "সূরা আশ-শারহ ৯৪:৬" and .fallback == false and .ar != "" and .bn != ""'

# A date set again reads nothing new, so the day changes first.
mode nobn
on_day 2026-11-02
on_day 2026-11-03
check "with deen answering 94:6 with no Bangla, 2026-11-03 draws its fallback quote in English ($(passage | jq -c '[.fallback, .kind, .label, .en, .ref]'))" \
  passage_is '.fallback == true and .kind == "ayah" and .label == "QUOTE" and .ar == "" and .bn == "" and .bn_pron == "" and .en != "" and .drawn[0][0].bn == ""'

mode fail
on_day 2026-11-04
check "with deen exiting 1, hadith day 2026-11-04 draws quote 92, Emerson's ($(passage | jq -c '[.kind, .entry, .fallback, .en, .ref]'))" \
  passage_is "$emerson and .fallback == true and .kind == \"hadith\" and .date == \"2026-11-04\""
check "it leaves no Arabic from the ayah day before ($(passage | jq -c '[.ar, .drawn[0][0].ar]'))" passage_is '.ar == "" and .drawn[0][0].ar == ""'
check "Paper labels it QUOTE, not HADITH ($(passage | jq -c '[.label, .drawn[0][0].label]'))" passage_is '.label == "QUOTE" and .drawn[0][0].label == "QUOTE"'

status_theme() { shell_status | jq -e --arg t "$1" '.theme == $t and .transition == ""' >/dev/null; }
in_theme() { "$repo/bin/dots" theme "$1" >/dev/null; until_ok 3000 status_theme "$1"; }
in_theme blueprint
until_ok 3000 passage_is '.drawn[0][0].label == "[QUOTE]"'
check "Blueprint labels it [QUOTE] ($(passage | jq -c '[.label, .drawn[0][0].label]'))" passage_is '.label == "[QUOTE]" and .drawn[0][0].label == "[QUOTE]"'
in_theme artboard
until_ok 3000 passage_is '.drawn[0][0].label == "Quote"'
check "Artboard labels it Quote ($(passage | jq -c '[.label, .drawn[0][0].label]'))" passage_is '.label == "Quote" and .drawn[0][0].label == "Quote"'
in_theme paper

on_day 2026-11-02
check "with deen exiting 1, quote day 2026-11-02 draws its own quote 89 ($(passage | jq -c '[.kind, .entry, .fallback, .en]'))" \
  passage_is '.kind == "quote" and .entry == 89 and .fallback == false and .en == "Action is the foundational key to all success."'

mode nocorpus
on_day 2026-11-08
check "with no hadith corpus, hadith day 2026-11-08 falls back ($(passage | jq -c '[.fallback, .ref]'))" passage_is '.fallback == true and .kind == "hadith"'
on_day 2026-11-11
check "with no hadith corpus, ayah day 2026-11-11 draws its ayah ($(passage | jq -c '[.fallback, .ref]'))" passage_is '.fallback == false and .kind == "ayah" and .ar != ""'

mode empty
on_day 2026-11-05
check "with deen answering {} for a dua, dua day 2026-11-05 falls back ($(passage | jq -c '[.fallback, .kind, .ref]'))" passage_is '.fallback == true and .kind == "dua" and .ar == ""'

mode long
on_day 2026-11-12
check "with deen answering a hadith 100,000 characters long, 2026-11-12 falls back ($(passage | jq -c '[.fallback, .kind, (.en | length)]'))" passage_is '.fallback == true and .kind == "hadith" and (.en | length) <= 280'

exit $((fails > 0))
}
