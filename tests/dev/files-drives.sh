#!/usr/bin/env bash
# In Files, a drive mounted under /run/media/$USER lists under DRIVES with its size and an e badge within 3 s; Enter on it opens its folder, and e on it unmounts it, deletes the loop device and takes it off the list within 3 s.
{
source "$(dirname "$0")/lib.sh"

files_qml=$repo/shell/files.qml
work=$(mktemp -d)
h=$work/home
log=$work/files.log
mkdir -p "$h/Documents" "$h/.config/gtk-3.0"
printf 'file://%s/Documents invoices\n' "$h" >"$h/.config/gtk-3.0/bookmarks"
img=$work/usb.img
mnt=/run/media/$USER/TESTUSB
loop=""
# The nested session's system bus is a double with no udisks, so the drive's commands, and Files' eject, use the real one.
udisks() { env -u DBUS_SYSTEM_BUS_ADDRESS udisksctl "$@" --no-user-interaction; }
# The loop device goes whatever happened, but only while it is still this check's image: an eject frees its number for another.
ours() { [ -n "$loop" ] && [ "$(losetup -n -O BACK-FILE "$loop" 2>/dev/null)" = "$img" ]; }
cleanup() {
  niri msg action close-window >/dev/null 2>&1
  [ -n "${automounter:-}" ] && kill "$automounter" 2>/dev/null
  if ours; then
    udisks unmount -b "$loop" >/dev/null 2>&1
    udisks loop-delete -b "$loop" >/dev/null 2>&1
  fi
  rm -rf "$work"
}

files_state() { timeout 0.5 qs ipc -p "$files_qml" call files state 2>/dev/null; }
files_is() { files_state | jq -e "$@" >/dev/null 2>&1; }
files_windows() { niri msg -j windows | jq '[.[] | select(.app_id == "files")] | length'; }
files_up() { [ "$(files_windows)" = 1 ] && files_is '.firstFrameMs != null and .listed'; }
status_theme() { shell_status | jq -e --arg t "$1" '.theme == $t' >/dev/null; }
no_transition() { shell_status | jq -e '.transition == ""' >/dev/null; }
in_theme() { "$repo/bin/dots" theme "$1" >/dev/null; until_ok 2000 status_theme "$1"; until_ok 2000 no_transition; sleep 0.3; }
mounted() { findmnt -n "$mnt" >/dev/null; }
listed() { files_is '.places | index("drives:TESTUSB") != null'; }
unlisted() { files_is '.places | index("drives:TESTUSB") == null'; }

niri msg action spawn -- sh -c "unset DBUS_SYSTEM_BUS_ADDRESS; HOME='$h' XDG_CONFIG_HOME='$h/.config' exec dots-files >>'$log' 2>&1"
until_ok 5000 files_up
in_theme paper
echo "     USER=$USER, the drives folder is $mnt"
check "before the drive, no TESTUSB in the places ($(files_state | jq -c .places))" unlisted

# The unit's own command automounts unless a udiskie already runs here (a v1 desktop starts one).
automounter=
if ! pgrep -x udiskie >/dev/null && ! pgrep -f '[b]in/udiskie' >/dev/null; then
  exec_start=$(sed -n 's/^ExecStart=//p' "$repo/home/dot_config/systemd/user/udiskie.service")
  env -u DBUS_SYSTEM_BUS_ADDRESS $exec_start >/dev/null 2>&1 &
  automounter=$!
  sleep 1
fi
truncate -s 20M "$img"
mkfs.vfat -n TESTUSB "$img" >/dev/null
setup=$(udisks loop-setup -f "$img" 2>&1)
loop=$(grep -o '/dev/loop[0-9]*' <<<"$setup")
check "udisksctl sets up a loop device for the image ($setup)" test -n "$loop"
until_ok 3000 mounted
check "udiskie automounts the drive at $mnt within 3 s" mounted
t0=$(now_ms)
until_ok 3000 listed
check "Files lists it under DRIVES in $(($(now_ms) - t0)) ms, between the pins and Trash ($(files_state | jq -c .places))" \
  files_is '[.places[] | split(":")[0] | {places: 0, pinned: 1, drives: 2, trash: 3}[.]] as $o | (.places | index("drives:TESTUSB")) != null and $o == ($o | sort) and $o[-2] == 2'

# Another drive may be mounted on this machine too: the head is the first drive row's, the words are TESTUSB's.
for theme in paper artboard blueprint; do
  in_theme "$theme"
  case $theme in
    paper) head=DRIVES row='{"label": "TESTUSB · 21 MB", "badge": "E", "lines": 1}' ;;
    artboard) head=Drives row='{"label": "TESTUSB · 21 MB", "badge": "e", "lines": 1}' ;;
    blueprint) head=DRIVES row='{"label": "TESTUSB · 21 MB", "badge": "E", "lines": 1}' ;;
  esac
  check "$theme: the drives read as its board does ($(files_state | jq -c .drives))" \
    files_is --arg h "$head" --argjson r "$row" '.drives[0].head == $h and ([.drives[] | select(.label | startswith("TESTUSB")) | del(.head)] == [$r])'
done
in_theme paper

wtype -k Tab
until_ok 1000 files_is '.side == "places"'
at=$(files_state | jq '.places | index("drives:TESTUSB") // 0')
for ((i = 0; i < at; i++)); do wtype j; done
until_ok 1000 files_is --argjson at "$at" '.placeAt == $at'
wtype -k Return
until_ok 2000 files_is --arg m "$mnt" '.listed and .folder == $m'
check "tab to the drive and Enter opens its mount folder ($(files_state | jq -c '{folder, side}'))" \
  files_is --arg m "$mnt" '.folder == $m and .side == "list"'

wtype -k Tab
until_ok 1000 files_is --argjson at "$at" '.side == "places" and .placeAt == $at'
wtype e
t0=$(now_ms)
until_ok 3000 unlisted
check "e on the drive takes it off the list in $(($(now_ms) - t0)) ms ($(files_state | jq -c '{places, driveError}'))" unlisted
check "and unmounts it" bash -c "! findmnt -n '$mnt' >/dev/null"
check "and deletes its loop device" bash -c "! losetup -n -O BACK-FILE '$loop' 2>/dev/null | grep -qxF '$img'"

errs=$(grep -E 'TypeError|ReferenceError|SyntaxError|Failed to load|is not a type|Cannot assign|Unable to assign|Cannot read propert|unavailable' "$log")
check "Files' log has no QML errors${errs:+: $(head -c 200 <<<"$errs")}" test -z "$errs"

exit $((fails > 0))
}
