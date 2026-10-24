#!/usr/bin/env bash
# Deen is an App: its desktop entry starts its own qs process with one window in the theme, five tabs that Tab walks, and Esc ends the process.
{
source "$(dirname "$0")/lib.sh"

deen_qml=$repo/shell/deen.qml
entry=$repo/home/dot_local/share/applications/deen.desktop
work=$(mktemp -d)
cleanup() { rm -rf "$work"; }
log=$work/deen.log

deen_state() { timeout 0.5 qs ipc -p "$deen_qml" call deen state 2>/dev/null; }
deen_is() { deen_state | jq -e "$@" >/dev/null 2>&1; }
deen_windows() { niri msg -j windows | jq '[.[] | select(.app_id == "deen")] | length'; }
deen_up() { [ "$(deen_windows)" = 1 ] && deen_is '.firstFrameMs != null'; }
deen_gone() { [ "$(deen_windows)" = 0 ]; }
# The App's own qs, found by its command line, never by pgrep -f, which matches this shell too.
deen_pids() {
  local pid
  for pid in $(pgrep -x qs); do
    tr '\0' ' ' 2>/dev/null <"/proc/$pid/cmdline" | grep -qF -- "-p $deen_qml" && echo "$pid"
  done
  return 0
}
no_deen_process() { [ -z "$(deen_pids)" ]; }
launcher_state() { timeout 0.5 qs ipc call launcher state 2>/dev/null; }
launcher_is() { launcher_state | jq -e "$1" >/dev/null 2>&1; }
status_theme() { shell_status | jq -e --arg t "$1" '.theme == $t and .transition == ""' >/dev/null; }
in_theme() { "$repo/bin/dots" theme "$1" >/dev/null; until_ok 3000 status_theme "$1"; }

# The nested shell scans the temp data dir's entries, so the repo's entry goes there for the launcher to list.
cp "$entry" "$DOTS_DEV_DIR/data/applications/deen.desktop"
niri msg action spawn -- dots-call launcher toggle
until_ok 3000 launcher_is '.open and .query == ""'
wtype deen
until_ok 3000 launcher_is '.query == "deen" and .results[0] == "Deen"'
check "the launcher lists Deen from its desktop entry ($(launcher_state | jq -c '.results[0:2]'))" launcher_is '.results[0] == "Deen"'
wtype -k Escape
until_ok 2000 launcher_is '.open == false'

# niri spawns the entry's Exec as the launcher would, with the App's stdout and stderr, where qs writes its warnings, in one log.
exec_line=$(sed -n 's/^Exec=//p' "$entry")
open_deen() { niri msg action spawn -- sh -c "exec $exec_line >>'$log' 2>&1"; }

in_theme paper
open_deen
until_ok 5000 deen_up
check "the entry's Exec ($exec_line) opens one window whose app id is deen ($(deen_windows))" deen_up
check "its first frame came $(deen_state | jq .firstFrameMs) ms after the process started, under 500" \
  deen_is '(.firstFrameMs | type) == "number" and .firstFrameMs > 0 and .firstFrameMs < 500'
check "its RSS is $(deen_state | jq .rssKiB) KiB, under 250 MiB" deen_is '(.rssKiB | type) == "number" and .rssKiB > 0 and .rssKiB < 256000'
check "it opens on Read, headed Read ($(deen_state | jq -c '[.tab, .heading]'))" deen_is '.tab == "read" and .heading == "Read"'
check "paper: the five tabs read READ to PRAYER with READ current ($(deen_state | jq -c .tabs))" \
  deen_is '.tabs == [{"text":"READ","current":true},{"text":"MEMORISE","current":false},{"text":"DUAS","current":false},{"text":"HADITH","current":false},{"text":"PRAYER","current":false}]'
check "Arabic draws in Amiri or Noto Naskh Arabic, a face with Arabic glyphs ($(deen_state | jq -c .arabic))" \
  deen_is '.arabic == "Amiri" or .arabic == "Noto Naskh Arabic"'

# Tab is pressed in the window itself, so it must reach the frame from whatever the page focuses.
wtype -k Shift_L
for want in memorise duas hadith prayer read; do
  wtype -k Tab
  until_ok 1000 deen_is --arg t "$want" '.tab == $t'
  check "Tab moves to $want ($(deen_state | jq -c '[.tab, .heading]'))" deen_is --arg t "$want" '.tab == $t and ([.tabs[] | select(.current)] | length) == 1'
done
wtype -M shift -k Tab -m shift
until_ok 1000 deen_is '.tab == "prayer"'
check "Shift+Tab moves back from Read to Prayer, headed Prayer ($(deen_state | jq -c '[.tab, .heading]'))" deen_is '.tab == "prayer" and .heading == "Prayer"'

in_theme artboard
until_ok 3000 deen_is '.voice == "plain"'
check "artboard: the tabs read in sentence case ($(deen_state | jq -c '[.tabs[].text]'))" deen_is '[.tabs[].text] == ["Read","Memorise","Duas","Hadith","Prayer"]'
in_theme blueprint
until_ok 3000 deen_is '.voice == "bracket"'
check "blueprint: the tabs read in capitals ($(deen_state | jq -c '[.tabs[].text]'))" deen_is '[.tabs[].text] == ["READ","MEMORISE","DUAS","HADITH","PRAYER"]'

wtype -k Escape
until_ok 3000 deen_gone
check "Esc closes the window" deen_gone
until_ok 3000 no_deen_process
check "and within 3 s no qs with -p .../shell/deen.qml is left" no_deen_process

errs=$(grep -E 'TypeError|ReferenceError|SyntaxError|Failed to load|is not a type|Cannot assign|Unable to assign|Cannot read propert|unavailable' "$log")
check "Deen's log has no QML errors${errs:+: $(head -c 200 <<<"$errs")}" test -z "$errs"

exit $((fails > 0))
}
