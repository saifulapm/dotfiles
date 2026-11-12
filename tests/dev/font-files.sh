#!/usr/bin/env bash
# Every surface opened, on text the check seeds, maps only the design's faces: Maple Mono, Adwaita Mono for the symbols it lacks, the emoji font, and the passage card's Amiri and Noto Sans Bengali with the Noto Sans fonts.conf pairs with it.
{
work=$(mktemp -d)
source "$(dirname "$0")/lib-deen-bangla.sh"
export DOTS_DEV_DEEN=$work/deen-bangla
source "$(dirname "$0")/lib.sh"
unset TMUX
cleanup() { rm -rf "$work"; }

paper_up() { niri msg -j layers | jq -e 'any(.[]; .namespace == "dots-paper")' >/dev/null; }
host_focus() { niri msg -j layers | jq -e --arg k "$1" 'any(.[]; .namespace == "dots-surfaces" and .keyboard_interactivity == $k)' >/dev/null; }
passage_is() { timeout 0.5 dots-call passage state 2>/dev/null | jq -e "$@" >/dev/null 2>&1; }
listed() { cliphist -db-path "$XDG_STATE_HOME/dots/clips.db" list 2>/dev/null | cut -f2- | grep -qxF "$1"; }

# Opens with "$@", waits for the keyboard, closes with the same target's close (or a second toggle).
open_close() {
  qs ipc call "$@" >/dev/null
  until_ok 3000 host_focus Exclusive || echo "     $* never took the keyboard"
  sleep 0.3
  if [ "$2" = toggle ]; then qs ipc call "$1" toggle >/dev/null; else qs ipc call "$1" close >/dev/null; fi
  until_ok 3000 host_focus None || echo "     $* never gave the keyboard back"
}

until_ok 10000 paper_up
pid=$(systemctl --user show -p MainPID --value "$DOTS_DEV_UNIT")
# The paper draws the day's passage, so the check sets the day: the first ayah, in Arabic, Bangla pronunciation and Bangla.
dots-call passage date 2026-11-03 >/dev/null
check "the paper draws the seeded ayah in Amiri and Noto Sans Bengali" until_ok 5000 passage_is '.kind == "ayah" and .fallback == false and .family.ar == "Amiri" and .family.bn == "Noto Sans Bengali"'
# The clipboard mode lists the nested session's own history, which holds only this copy.
wl-copy "font check clip"
until_ok 3000 listed "font check clip" || echo "     the seeded clip never reached the history"
for t in launcher notifs cheatsheet control goals; do open_close "$t" open; done
open_close launcher mode emoji
open_close launcher mode clipboard
open_close record toggle
# The legends' symbols, which Maple Mono lacks.
notify-send artboard "Enter ↵ space ␣ ctrl ⌃ level ▮"
sleep 1

files=$(grep -oE '/[^ ]+\.(ttf|otf|ttc)' "/proc/$pid/maps" | sort -u | xargs -rn1 basename)
echo "     font files: $(tr '\n' ' ' <<<"$files")"
others=$(grep -vE '^(MapleMono|AdwaitaMono)-|^Noto-COLRv1\.ttf$|^Amiri-Regular\.ttf$|^NotoSansBengali\[wght\]\.ttf$|^NotoSans\[wght\]\.ttf$' <<<"$files")
check "no other font file is mapped${others:+: $(tr '\n' ' ' <<<"$others")}" test -z "$others"
check "Adwaita Mono draws the symbols" grep -q '^AdwaitaMono-' <<<"$files"

exit $((fails > 0))
}
