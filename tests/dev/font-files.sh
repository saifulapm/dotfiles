#!/usr/bin/env bash
# Every surface opened maps only the design's faces, Adwaita Mono for the symbols Maple Mono lacks, and the emoji font.
{
source "$(dirname "$0")/lib.sh"
unset TMUX

paper_up() { niri msg -j layers | jq -e 'any(.[]; .namespace == "dots-paper")' >/dev/null; }
host_focus() { niri msg -j layers | jq -e --arg k "$1" 'any(.[]; .namespace == "dots-surfaces" and .keyboard_interactivity == $k)' >/dev/null; }

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
for t in launcher notifs cheatsheet control goals; do open_close "$t" open; done
open_close launcher mode emoji
open_close launcher mode clipboard
open_close record toggle
# The legends' symbols, which Maple Mono lacks.
notify-send artboard "Enter ↵ space ␣ ctrl ⌃ level ▮"
sleep 1

files=$(grep -oE '/[^ ]+\.(ttf|otf|ttc)' "/proc/$pid/maps" | sort -u | xargs -rn1 basename)
echo "     font files: $(tr '\n' ' ' <<<"$files")"
others=$(grep -vE '^(MapleMono|InstrumentSerif|AdwaitaMono)-|^Noto-COLRv1\.ttf$' <<<"$files")
check "no other font file is mapped${others:+: $(tr '\n' ' ' <<<"$others")}" test -z "$others"
check "Adwaita Mono draws the symbols" grep -q '^AdwaitaMono-' <<<"$files"

exit $((fails > 0))
}
