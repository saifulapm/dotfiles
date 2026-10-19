#!/usr/bin/env bash
# The margins read in each theme's voice: 02 — FOOT · ~, Page 02 / foot — ~ and [02] FOOT — ~, each with its own date.
{
source "$(dirname "$0")/lib.sh"

margins() { timeout 0.5 qs ipc call margins state 2>/dev/null; }
drawn_is() { margins | jq -e --arg want "$2" ".drawn.$1 == \$want" >/dev/null 2>&1; }
status_theme() { shell_status | jq -e --arg t "$1" '.theme == $t' >/dev/null; }
in_theme() { "$repo/bin/dots" theme "$1" >/dev/null; until_ok 2000 status_theme "$1"; }

until_ok 5000 shell_status >/dev/null
# niri drops an empty workspace once focus leaves it, so workspace 1 keeps a window of its own.
niri msg action spawn -- foot sleep 600
until_ok 5000 eval 'niri msg -j windows | jq -e "length == 1" >/dev/null'
niri msg action focus-workspace 2
# sleep never retitles its window the way a shell does, so the title stays ~.
niri msg action spawn -- foot -T '~' sleep 600
foot_focused() { niri msg -j windows | jq -e 'any(.[]; .app_id == "foot" and .title == "~" and .is_focused)' >/dev/null; }
until_ok 5000 foot_focused

# Each date reads in its theme's form.
date_ends() { margins | jq -e --arg d "$1" '.drawn.right | endswith($d)' >/dev/null 2>&1; }

in_theme paper
until_ok 2000 drawn_is left "02 — FOOT · ~"
echo "     drawn: $(margins | jq -c .drawn)"
check "paper: the top-left reads 02 — FOOT · ~" drawn_is left "02 — FOOT · ~"
check "paper: the date reads $(LC_ALL=C date +'%a %-d %b' | tr a-z A-Z)" date_ends "$(LC_ALL=C date +'%a %-d %b' | tr a-z A-Z)"

in_theme artboard
until_ok 2000 drawn_is left "Page 02 / foot — ~"
echo "     drawn: $(margins | jq -c .drawn)"
check "artboard: the top-left reads Page 02 / foot — ~" drawn_is left "Page 02 / foot — ~"
check "artboard: the date reads $(LC_ALL=C date +'%a %-d %b')" date_ends "$(LC_ALL=C date +'%a %-d %b')"

in_theme blueprint
until_ok 2000 drawn_is left "[02] FOOT — ~"
echo "     drawn: $(margins | jq -c .drawn)"
check "blueprint: the top-left reads [02] FOOT — ~" drawn_is left "[02] FOOT — ~"
check "blueprint: the date reads $(date +%F)" date_ends "$(date +%F)"

exit $((fails > 0))
}
