#!/usr/bin/env bash
# The daily passage in Bangla on the real deen and the texts it builds from deen-data: the date override over the four kinds, each kind's lines as drawn, each theme's design and Bengali face and a switch between them, every day of the list fitting the output, back to today, read through passage state.
{
work=$(mktemp -d)
source "$(dirname "$0")/lib-deen-bangla.sh"
export DOTS_DEV_DEEN=$work/deen-bangla
source "$(dirname "$0")/lib.sh"
cleanup() { rm -rf "$work"; }
deen() { "$work/deen-bangla" "$@"; }

passage() { timeout 0.5 dots-call passage state 2>/dev/null; }
passage_is() { passage | jq -e "$@" >/dev/null 2>&1; }
drew='(.bn != "" or .en != "")'
on_day() { dots-call passage date "$1" && until_ok 3000 passage_is --arg d "$1" ".date == \$d and $drew"; }

until_ok 5000 shell_status >/dev/null
until_ok 5000 passage_is "$drew"
today=$(date +%F)
check "with no date set the passage is today's, $today ($(passage | jq -c '[.date, .kind, .ref]'))" passage_is --arg d "$today" '.date == $d and .fallback == false'

on_day 2026-11-03
ayah=$(deen api ayah 94:6 | jq -c .ayah)
check "2026-11-03 is the first ayah, 94:6, its reference in Bangla digits ($(passage | jq -c '[.kind, .entry, .ref]'))" passage_is '.kind == "ayah" and .entry == 0 and .ref == "সূরা আশ-শারহ ৯৪:৬" and .day == 20760'
# deen spells shadda before fatha, so the Arabic and the engine's pronunciation are checked against its own answer, not a typed copy.
check "its Arabic, Bangla pronunciation and Bangla meaning are deen's, and no English ($(passage | jq -c '[.bn_pron, .bn, .en]'))" \
  passage_is --argjson a "$ayah" '.ar == $a.ar and .bn_pron == $a.bn_pron and $a.bn_pron != "" and .bn == "নিশ্চয় কষ্টের সাথেই স্বস্তি আছে।" and .en == ""'

# A second date set while deen still reads the first ends on the second day's own text, never the first's.
dots-call passage date 2026-11-11 && dots-call passage date 2026-11-07
until_ok 3000 passage_is ".date == \"2026-11-07\" and $drew"
bn=$(deen api ayah 2:152 | jq -r .ayah.bn)
check "two ayah days set inside one deen call end on 2026-11-07's own ayah, 2:152 ($(passage | jq -c '[.date, .ref, .bn[0:30]]'))" \
  passage_is --arg bn "$bn" '.date == "2026-11-07" and .ref == "সূরা আল-বাক্বারাহ ২:১৫২" and .bn == $bn'

on_day 2026-11-04
check "2026-11-04 is the first hadith, bukhari:6807, in Bangla only, its narrator in the text ($(passage | jq -c '[.kind, .entry, .ref, .bn[0:30]]'))" \
  passage_is '.kind == "hadith" and .entry == 0 and .ref == "সহীহ বুখারী ৬৮০৭" and .ar == "" and .bn_pron == "" and .en == "" and (.bn | startswith("সাহল ইবনু সা‘দ"))'

on_day 2026-11-01
dua=$(deen dua show 235 | jq -c .dua)
check "2026-11-01 is the 30th dua, Hisnul Muslim 235, in Arabic, the Bangla book's pronunciation and meaning ($(passage | jq -c '[.kind, .entry, .ref, .bn[0:30]]'))" \
  passage_is --argjson d "$dua" '.kind == "dua" and .entry == 29 and .ref == "হিসনুল মুসলিম ২৩৫" and .ar == $d.ar and .bn_pron == $d.bn_pron and .bn == $d.bn and .en == ""'

on_day 2026-11-02
check "2026-11-02 is quote 89, Picasso's, in English ($(passage | jq -c '[.kind, .entry, .en, .ref]'))" \
  passage_is '.kind == "quote" and .entry == 89 and .en == "Action is the foundational key to all success." and .ref == "Pablo Picasso" and .bn == ""'

# What the paper on screen draws, from its sheet's own Text items.
drawn() { passage | jq -c ".drawn[0][0] | ${1:-.}"; }
drawn_is() { passage | jq -e --arg arabic "$arabic" --arg bengali "$bengali" "(.drawn | length) == 1 and (.drawn[0] | length) == 1 and (.drawn[0][0] | $1)" >/dev/null 2>&1; }
on_drawn() { dots-call passage date "$1" && until_ok 3000 drawn_is "$2"; }
status_theme() { shell_status | jq -e --arg t "$1" '.theme == $t and .transition == ""' >/dev/null; }
in_theme() { "$repo/bin/dots" theme "$1" >/dev/null; until_ok 3000 status_theme "$1"; }
# A theme switch is done when the sheet it left draws nothing.
switched() { in_theme "$1" && until_ok 3000 drawn_is "$2"; }
arabic=Amiri
fc-list : family | grep -qx Amiri || arabic="Noto Naskh Arabic"
# Each drawn Bangla line, and the reference, in the theme's Bengali face; no Latin letter or digit in any line.
in_bangla='.family.bn_pron == $bengali and .family.bn == $bengali and .family.ref == $bengali and .en == "" and ([.ar, .bn_pron, .bn, .ref] | all(test("[A-Za-z0-9]") | not))'
# Saved for Saiful to set beside the boards, when the run names a folder.
shot() { [ -z "${DOTS_PASSAGE_SHOTS:-}" ] || grim -o "$(niri msg -j outputs | jq -r 'keys[0]')" "$DOTS_PASSAGE_SHOTS/$1.png"; }
out=$(niri msg -j outputs | jq -c 'first(.[]).logical')
centred() { passage | jq -e --argjson o "$out" '.drawn[0][0].box | ((.x + .w / 2) - ($o.width / 2) | fabs) < 2 and ((.y + .h / 2) - ($o.height / 2) | fabs) < 2' >/dev/null; }
# Clear of the island and the margins, 95 px each side.
fits() { passage | jq -e --argjson o "$out" '.drawn[0][0].box | .y >= 95 and .y + .h <= $o.height - 95' >/dev/null; }
fits_centred() { fits && centred; }

in_theme paper
bengali="Noto Serif Bengali"
on_drawn 2026-11-03 '.ref == "সূরা আশ-শারহ ৯৪:৬"'
check "Paper draws 94:6's Arabic in $arabic, its pronunciation, meaning and reference upright in $bengali, no Latin ($(drawn '[.family, .bn]'))" \
  drawn_is '.family.ar == $arabic and .ar != "" and .bn_pron != "" and .bn == "নিশ্চয় কষ্টের সাথেই স্বস্তি আছে।" and '"$in_bangla"
check "Paper's label is AYAH in Maple Mono ($(passage | jq -c '[.label, .drawn[0][0].label, .drawn[0][0].family.label]'))" \
  passage_is '.label == "AYAH" and .drawn[0][0].label == "AYAH" and .drawn[0][0].family.label == "Maple Mono"'
check "the block sits centred on the output ($(drawn .box), output $out)" centred
shot paper-ayah
on_drawn 2026-11-04 '.ref == "সহীহ বুখারী ৬৮০৭"'
check "Paper draws bukhari:6807 under HADITH, its Bangla in $bengali with no Arabic line ($(drawn '[.label, .ar, .family.bn, .bn[0:30]]'))" \
  drawn_is '.label == "HADITH" and .ar == "" and .bn_pron == "" and (.bn | startswith("সাহল ইবনু সা‘দ")) and .family.bn == $bengali and .family.ref == $bengali'
check "its punctuation draws at a proportional width, under a third of an em ($(drawn .bnComma))" drawn_is '.bnComma > 0 and .bnComma < 0.34'
shot paper-hadith

switched blueprint '.label == "[HADITH]"'
bengali="Noto Sans Bengali"
check "Blueprint labels bukhari:6807 [HADITH], its Bangla reference as deen names it ($(passage | jq -c '[.label, .ref, .drawn[0][0].ref]'))" \
  passage_is '.label == "[HADITH]" and .ref == "সহীহ বুখারী ৬৮০৭" and .drawn[0][0].ref == "সহীহ বুখারী ৬৮০৭"'
check "after the switch settles one sheet draws the passage, its Bangla in $bengali ($(drawn '.family'))" drawn_is '.label == "[HADITH]" and .family.bn == $bengali and .family.ref == $bengali'
# Noto Sans Bengali has no comma, colon or brackets; a monospace fallback drew them wide and apart from their words.
check "its punctuation draws at a proportional width, under a third of an em ($(drawn .bnComma))" drawn_is '.bnComma > 0 and .bnComma < 0.34'
shot blueprint-hadith
on_drawn 2026-11-03 '.label == "[AYAH]"'
check "Blueprint draws 94:6 under [AYAH], its Bangla lines in $bengali, no Latin ($(drawn '[.label, .ref, .family]'))" \
  drawn_is '.label == "[AYAH]" and .ref == "সূরা আশ-শারহ ৯৪:৬" and .family.ar == $arabic and '"$in_bangla"
shot blueprint-ayah

switched artboard '.label == "Ayah"'
check "Artboard labels it Ayah over the card, its Bangla lines in $bengali, no Latin ($(drawn '[.label, .ref, .family]'))" \
  drawn_is '.label == "Ayah" and .ref == "সূরা আশ-শারহ ৯৪:৬" and '"$in_bangla"
on_drawn 2026-11-04 '.label == "Hadith"'
check "Artboard labels bukhari:6807 Hadith ($(drawn '[.label, .ref, .family.bn]'))" drawn_is '.label == "Hadith" and .ref == "সহীহ বুখারী ৬৮০৭" and .family.bn == $bengali'
check "its punctuation draws at a proportional width, under a third of an em ($(drawn .bnComma))" drawn_is '.bnComma > 0 and .bnComma < 0.34'
on_drawn 2026-11-01 '.ref == "হিসনুল মুসলিম ২৩৫"'
check "Artboard draws dua 235 in Arabic, the Bangla book's pronunciation and meaning, no Latin ($(drawn '[.label, .family]'))" drawn_is '.label == "Dua" and .ar != "" and '"$in_bangla"
shot artboard-dua

in_theme paper
bengali="Noto Serif Bengali"
on_drawn 2027-01-23 '.ref == "সহীহ মুসলিম ৬৬০২"'
check "muslim:6602 draws its cleaned Bangla: no chain stub, no publisher note ($(drawn '.bn'))" \
  drawn_is '.bn != "" and (.bn | contains(".....") | not) and (.bn | contains("(ইসলামিক ফাউন্ডেশন") | not) and (.bn | startswith("নবী সাল্লাল্লাহু"))'
# bukhari:6014's Bangla is the list's longest drawn line, 256 characters.
on_drawn 2026-12-22 '.ref == "সহীহ বুখারী ৬০১৪"'
check "bukhari:6014's Bangla wraps over lines of one pitch, none opened wider by a conjunct ($(drawn .bnLines))" \
  drawn_is '.bnLines.count > 1 and .bnLines.height < .bnLines.count * .bnLines.pitch + .bnLines.pitch / 8'
on_drawn 2026-11-21 '.ref == "হিসনুল মুসলিম ১৬"'
check "dua 16 draws its Arabic in $arabic over its Bangla ($(drawn '[.family.ar, .bn[0:30]]'))" drawn_is '.family.ar == $arabic and .ar != "" and .bn != "" and .bn_pron != ""'
on_drawn 2026-12-24 '.ref == "Walt Disney"'
check "Walt Disney's quote draws its English sentence in Instrument Serif over his name ($(drawn '[.en, .family.en, .family.ref]'))" \
  drawn_is '.en == "The best way to get started is to quit talking and begin doing." and .ar == "" and .bn == "" and .family.en == "Instrument Serif" and .family.ref == "Instrument Serif"'
on_drawn 2027-01-09 '.ref == "Henry Ford"'
check "Henry Ford's quote splits at its last dash ($(drawn .en))" drawn_is '.en == "Whether you think you can, or you think you can'"'"'t — you'"'"'re right."'

# Dua 108, its meaning 213 characters under its Arabic and pronunciation, is the list's tallest dua; it draws clear of the island and margins in each theme.
for theme in paper blueprint artboard; do
  in_theme "$theme"
  on_drawn 2026-12-31 '.ref == "হিসনুল মুসলিম ১০৮"'
  check "$theme: dua 108's three lines fit between the island and the bottom margin, centred ($(drawn .box), output $out)" fits_centred
done

# Every day of the list's 120-day turn, in each theme, draws inside the same room.
for theme in paper blueprint artboard; do
  in_theme "$theme"
  over=()
  for i in $(seq 0 119); do
    day=$(date -d "2026-11-01 + $i days" +%F)
    on_day "$day" && until_ok 3000 drawn_is '.box.h > 0'
    fits || over+=("$day $(drawn '[.ref, .box.h]')")
  done
  check "$theme: all 120 days fit between the island and the bottom margin (${over[*]:-none over})" test ${#over[@]} = 0
done
in_theme paper

on_day 2026-11-02
dots-call passage date 2026-02-30
check "a date that is no day is refused, and the quote stays" passage_is '.date == "2026-11-02"'

dots-call passage date ""
until_ok 3000 passage_is --arg d "$today" ".date == \$d and $drew"
check "an empty date returns to today, $today ($(passage | jq -r .date))" passage_is --arg d "$today" ".date == \$d and $drew"

exit $((fails > 0))
}
