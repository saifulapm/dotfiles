#!/usr/bin/env bash
# The urgency marks in each theme's voice: !05 !07 in red, • 05  • 07 with accent dots, [!05][!07] in amber; with every mark drawn a long title still elides short of the island.
{
source "$(dirname "$0")/lib.sh"

margins() { timeout 0.5 qs ipc call margins state 2>/dev/null; }
marks_are() { margins | jq -e --arg want "$1" '.drawn.marks == $want' >/dev/null 2>&1; }
colors_are() { margins | jq -e --argjson want "$1" '.drawn.markColors | unique == ($want | sort)' >/dev/null 2>&1; }
focused_is() { niri msg -j focused-window | jq -e --arg t "$1" '.title == $t' >/dev/null 2>&1; }
status_theme() { shell_status | jq -e --arg t "$1" '.theme == $t' >/dev/null; }
in_theme() { "$repo/bin/dots" theme "$1" >/dev/null; until_ok 2000 status_theme "$1"; }
bells="$DOTS_DEV_DIR/bells"
mkdir -p "$bells"
ringer() { niri msg action spawn -- foot -c /dev/null -o bell.urgent=yes -T "$1" sh -c "until [ -e '$bells/$1' ]; do sleep 0.05; done; printf '\a'; sleep 600"; until_ok 5000 focused_is "$1"; }
plain() { niri msg action spawn -- foot -c /dev/null -T "$1" sleep 600; until_ok 5000 focused_is "$1"; }

until_ok 5000 shell_status >/dev/null
# Workspace 1 shows a 200-character title, and 4 and 6 hold quiet feet so every number up to 7 stays.
long=$(printf 'T%.0s' $(seq 200))
plain "$long"
for n in 2 3 4 5 6 7; do
  niri msg action focus-workspace "$n"
  case $n in 4 | 6) plain "quiet$n" ;; *) ringer "ws$n" ;; esac
done
niri msg action focus-workspace 1
until_ok 2000 focused_is "$long"

touch "$bells/ws5" "$bells/ws7"
in_theme paper
until_ok 3000 marks_are "!05 !07"
echo "     drawn: $(margins | jq -c .drawn)"
check "paper: the marks read !05 !07" marks_are "!05 !07"
check "paper: in danger #C8381E" colors_are '["#c8381e"]'
in_theme artboard
until_ok 2000 marks_are "• 05  • 07"
check "artboard: the marks read • 05  • 07" marks_are "• 05  • 07"
check "artboard: accent dots before ink numbers" colors_are '["#3d5afe","#15171b"]'
in_theme blueprint
until_ok 2000 marks_are "[!05][!07]"
check "blueprint: the marks read [!05][!07]" marks_are "[!05][!07]"
check "blueprint: in amber #FFB547" colors_are '["#ffb547"]'

touch "$bells/ws2" "$bells/ws3"
# A Text paints past its width unless it elides, so the check reads both its box and its elision.
short_of_island() { margins | jq -e '.drawn.leftElided and .drawn.leftEnd <= .drawn.lineEnd and .drawn.leftEnd > .drawn.lineEnd - 40' >/dev/null 2>&1; }
for t in paper:'!02 !03 !05 +1' artboard:'• 02  • 03  • 05  +1' blueprint:'[!02][!03][!05][+1]'; do
  in_theme "${t%%:*}"
  until_ok 3000 marks_are "${t#*:}"
  until_ok 2000 short_of_island
  echo "     ${t%%:*}: $(margins | jq -c '.drawn | {marks, leftEnd, lineEnd}')"
  check "${t%%:*}: ${t#*:} after a 200-character title that elides 8 px short of the island" eval 'marks_are "${t#*:}" && short_of_island'
done

exit $((fails > 0))
}
