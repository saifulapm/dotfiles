#!/usr/bin/env bash
# Files' y and x then p copy and move the marked files with a progress line ctrl+c stops; a name that exists keeps both, a folder never goes into itself, and a full drive stops on its file with r, s and esc.
{
source "$(dirname "$0")/lib.sh"

files_qml=$repo/shell/files.qml
work=$(mktemp -d)
h=$work/home
loop=
cleanup() {
  if [ -n "$loop" ]; then
    udisks unmount -b "$loop" --no-user-interaction >/dev/null 2>&1
    udisks loop-delete -b "$loop" --no-user-interaction >/dev/null 2>&1
  fi
  rm -rf "$work"
}
mkdir -p "$h/Downloads/screenshots" "$h/Documents" "$h/Pictures" "$h/Codes"
printf 'one' >"$h/Downloads/IMG_2039.jpg"
printf 'two' >"$h/Downloads/IMG_2040.jpg"
printf 'new notes' >"$h/Downloads/notes.txt"
printf 'old notes' >"$h/Documents/notes.txt"
head -c 96000000 /dev/urandom >"$h/Pictures/setup-1.4.2.AppImage"
log=$work/files.log
# The nested session's system bus is a stand-in with no udisks, so udisksctl talks to the real one.
udisks() { env -u DBUS_SYSTEM_BUS_ADDRESS udisksctl "$@"; }

files_state() { timeout 2 qs ipc -p "$files_qml" call files state 2>/dev/null; }
files_is() { files_state | jq -e "$@" >/dev/null 2>&1; }
focused() { niri msg -j windows | jq -e 'any(.[]; .app_id == "files" and .is_focused)' >/dev/null; }
open_files() {
  niri msg action spawn -- sh -c "HOME='$h' XDG_CONFIG_HOME='$h/.config' exec dots-files >>'$log' 2>&1"
  until_ok 8000 files_is '.listed and .firstFrameMs != null'
  until_ok 3000 focused
}
close_files() {
  niri msg action close-window --id "$(niri msg -j windows | jq -r 'first(.[] | select(.app_id == "files") | .id)')"
  until_ok 3000 bash -c "! niri msg -j windows | jq -e 'any(.[]; .app_id == \"files\")' >/dev/null"
}
go() {
  wtype "/$1"
  until_ok 3000 files_is --arg f "$2" '.listed and (.folder | endswith($f))'
}

open_files
go down /Downloads
wtype /IMG
wtype -k Return
until_ok 1000 files_is '.rows == ["IMG_2039.jpg", "IMG_2040.jpg"]'
wtype -k space -k space
wtype y
until_ok 1000 files_is '.op.yank == "copy 2"'
go code /Codes
wtype p
until_ok 3000 files_is '.op.running == false and (.rows | length) == 2'
check "y on two marked files, then p in Codes, copies both ($(files_state | jq -c .rows))" \
  bash -c "[ \"\$(cat '$h/Codes/IMG_2039.jpg')\" = one ] && [ \"\$(cat '$h/Codes/IMG_2040.jpg')\" = two ] && [ -f '$h/Downloads/IMG_2039.jpg' ]"
wtype -k space -k space
wtype x
until_ok 1000 files_is '.op.yank == "move 2"'
go pic /Pictures
wtype p
until_ok 3000 bash -c "[ -f '$h/Pictures/IMG_2039.jpg' ] && [ ! -e '$h/Codes/IMG_2039.jpg' ]"
check "x then p moves them out of Codes into Pictures" \
  bash -c "[ -f '$h/Pictures/IMG_2040.jpg' ] && [ ! -e '$h/Codes/IMG_2040.jpg' ] && [ -z \"\$(ls '$h/Codes')\" ]"
until_ok 1000 files_is '.op.yank == ""'
check "and a finished move forgets what it moved" files_is '.op.yank == ""'

go down /Downloads
wtype /notes
wtype -k Return
wtype y
go docu /Documents
wtype p
until_ok 3000 files_is '.rows == ["notes (1).txt", "notes.txt"]'
check "pasting notes.txt into a folder that has one keeps both, the new one notes (1).txt" \
  bash -c "[ \"\$(cat '$h/Documents/notes.txt')\" = 'old notes' ] && [ \"\$(cat '$h/Documents/notes (1).txt')\" = 'new notes' ]"

go down /Downloads
wtype /screen
wtype -k Return
wtype y
wtype l
until_ok 2000 files_is '.listed and (.folder | endswith("/screenshots"))'
wtype p
until_ok 3000 files_is '.notice != ""'
check "pasting a folder into itself is refused and the status line says so ($(files_state | jq -c .status.counts))" \
  files_is '.status.counts == "screenshots cannot go into itself"'
check "and nothing was made inside it" bash -c "[ -z \"\$(ls '$h/Downloads/screenshots')\" ]"
close_files

# A 96 MB copy takes about 35 ms here, too quick to watch, so the op is stopped as it starts and let go after ctrl+c; the [d] keeps pgrep from matching this shell.
open_files
go pic /Pictures
wtype /setup
wtype -k Return
wtype y
go down /Downloads
( for _ in $(seq 2000); do op=$(pgrep -f '[d]ots-files-op (copy|move)') && { kill -STOP $op; echo "$op" >"$work/op.pid"; exit; }; done ) &
wtype p
until_ok 5000 test -s "$work/op.pid"
# Stopped before it summed its sources, the op runs in slices of well under a millisecond until the line has a size.
op=$(cat "$work/op.pid")
python3 - "$op" "$files_qml" <<'PY'
import json, os, signal, subprocess, sys, time
op, qml = int(sys.argv[1]), sys.argv[2]
for _ in range(400):
    out = subprocess.run(["timeout", "2", "qs", "ipc", "-p", qml, "call", "files", "state"], capture_output=True, text=True).stdout
    try:
        if "of 96 MB" in json.loads(out)["op"]["progress"]:
            break
    except (ValueError, KeyError):
        pass
    os.kill(op, signal.SIGCONT)
    time.sleep(0.0005)
    os.kill(op, signal.SIGSTOP)
PY
check "a 96 MB copy shows its progress line ($(files_state | jq -c '[.op.say, .op.progress, .op.keys]'))" \
  files_is '(.op.say == "copying 1 file from ~/Pictures") and (.op.progress | test("^[0-9]+% · [0-9.]+ of 96 MB")) and .op.keys == "ctrl+c cancels"'
wtype p
until_ok 2000 files_is '.notice != ""'
check "p while the copy runs says so and starts nothing ($(files_state | jq -c .notice))" files_is '.notice == "a copy is running; wait for it to finish" and .op.running'
wtype -M ctrl c -m ctrl
sleep 0.3
kill -CONT "$op"
until_ok 5000 files_is '.op.running == false'
check "ctrl+c cancels it, leaving no partial file ($(ls "$h/Downloads" | tr '\n' ' '))" \
  bash -c "[ ! -e '$h/Downloads/setup-1.4.2.AppImage' ] && ! ls '$h/Downloads' | grep -q AppImage"
close_files

# A full drive: a loop device with a small FAT filesystem, mounted under /run/media/$USER as a USB drive is.
truncate -s 4M "$work/drive.img"
mkfs.vfat -n FULLDRIVE "$work/drive.img" >/dev/null
loop=$(udisks loop-setup -f "$work/drive.img" --no-user-interaction | grep -o '/dev/loop[0-9]*')
mounted() { findmnt -n -o TARGET "$loop" >/dev/null; }
until_ok 3000 mounted || udisks mount -b "$loop" --no-user-interaction >/dev/null
drive=$(findmnt -n -o TARGET "$loop")
# Everything below writes and deletes on the drive, so it stops unless the drive is the loop just made.
case $drive in
  /run/media/"$USER"/FULLDRIVE) ;;
  *) check "the loop drive mounted under /run/media/$USER (loop '$loop', mount '$drive')" false; exit 1 ;;
esac
free=$(($(stat -f -c '%a * %S' "$drive")))
mkdir -p "$h/Downloads/big"
head -c $((free * 3 / 10)) /dev/urandom >"$h/Downloads/big/a.bin"
head -c $((free * 3 / 10)) /dev/urandom >"$h/Downloads/big/b.bin"
head -c $((free * 6 / 10)) /dev/urandom >"$h/Downloads/big/c.bin"
head -c $((free / 20)) /dev/urandom >"$h/Downloads/big/d.bin"
echo "     drive $drive on $loop, $free bytes free"

# Copies the four onto the drive and waits for the failure card.
copy_to_drive() {
  wtype /big
  wtype -k Return
  until_ok 1000 files_is '.rows == ["big"]'
  wtype l
  until_ok 3000 files_is '.listed and (.folder | endswith("/big")) and (.rows | length) == 4'
  wtype -k space -k space -k space -k space
  wtype y
  wtype -k Tab
  local at
  at=$(files_state | jq '.places | index("drives:FULLDRIVE")')
  until_ok 1000 files_is '.side == "places"'
  for ((i = $(files_state | jq .placeAt); i < at; i++)); do wtype j; done
  wtype -k Return
  until_ok 3000 files_is --arg d "$drive" '.listed and .folder == $d'
  wtype p
  until_ok 8000 files_is '.op.card != null'
}
open_files
go down /Downloads
copy_to_drive
check "a copy onto a full drive stops on c.bin with the card up ($(files_state | jq -c '.op.card | {title, rows: [.rows[].state]}'))" \
  files_is '.op.card.title == "FULLDRIVE is full" and ([.op.card.rows[].state] | (.[0] | startswith("copied")) and (.[1] | startswith("copied")) and .[2] == "stopped · partial removed" and (.[3] | startswith("not started")))'
check "it reports 2 of 4 copied on the status line ($(files_state | jq -c .status))" files_is '.status.counts == "copy to FULLDRIVE stopped" and .status.at == "2 of 4 copied"'
check "and leaves no partial c.bin ($(ls "$drive" | tr '\n' ' '))" bash -c "[ ! -e '$drive/c.bin' ]"
wtype s
until_ok 5000 files_is '.op.running == false'
check "s skips c.bin and copies d.bin ($(ls "$drive" | tr '\n' ' '))" bash -c "[ -f '$drive/a.bin' ] && [ -f '$drive/b.bin' ] && [ ! -e '$drive/c.bin' ] && cmp -s '$drive/d.bin' '$h/Downloads/big/d.bin'"
rm -f "$drive"/*.bin
close_files

open_files
go down /Downloads
copy_to_drive
wtype -k Escape
until_ok 5000 files_is '.op.running == false'
check "esc cancels the rest: a and b stay whole, no c or d ($(ls "$drive" | tr '\n' ' '); $(files_state | jq -c .notice))" \
  bash -c "cmp -s '$drive/a.bin' '$h/Downloads/big/a.bin' && cmp -s '$drive/b.bin' '$h/Downloads/big/b.bin' && [ ! -e '$drive/c.bin' ] && [ ! -e '$drive/d.bin' ]"
check "and the status line says the copy stopped" files_is '.notice == "copy to FULLDRIVE stopped · 2 of 4 copied"'
rm -f "$drive"/*.bin
close_files

open_files
go down /Downloads
copy_to_drive
# Room for c.bin: the two copied files go.
rm -f "$drive/a.bin" "$drive/b.bin"
wtype r
until_ok 5000 files_is '.op.running == false'
check "r after room is made retries c.bin and finishes ($(ls "$drive" | tr '\n' ' '))" \
  bash -c "cmp -s '$drive/c.bin' '$h/Downloads/big/c.bin' && cmp -s '$drive/d.bin' '$h/Downloads/big/d.bin'"
close_files

for t in artboard blueprint; do
  "$repo/bin/dots" theme "$t" >/dev/null
  rm -f "$drive"/*.bin
  open_files
  go down /Downloads
  copy_to_drive
  echo "     $t card: $(files_state | jq -c '.op.card | {head, title, keys, s: .rows[2].state}')"
  case $t in
    artboard) want='.op.card.head == "Copy failed" and .op.card.keys == "r retry · s skip this file · esc cancel the rest"' ;;
    blueprint) want='.op.card.head == "COPY FAILED" and .op.card.title == "FULLDRIVE IS FULL" and .op.card.keys == "[R] RETRY · [S] SKIP THIS FILE · [ESC] CANCEL THE REST" and .op.card.rows[2].state == "STOPPED · PARTIAL REMOVED"' ;;
  esac
  check "$t: the card's words read as its board does" files_is "$want"
  wtype -k Escape
  until_ok 5000 files_is '.op.running == false'
  close_files
done
"$repo/bin/dots" theme paper >/dev/null

# Thirty files onto the full drive: the card lists them in a scrolled list and stays inside the window.
rm -f "$drive"/*.bin
head -c "$free" /dev/zero >"$drive/fill.bin" 2>/dev/null
mkdir -p "$h/Downloads/thirty"
for i in $(seq -w 1 30); do head -c 4096 /dev/urandom >"$h/Downloads/thirty/t$i.bin"; done
open_files
go down /Downloads
wtype /thirty
wtype -k Return
wtype l
until_ok 3000 files_is '.listed and (.folder | endswith("/thirty")) and (.rows | length) == 30'
for i in $(seq 30); do wtype -k space; done
wtype y
wtype -k Tab
at=$(files_state | jq '.places | index("drives:FULLDRIVE")')
for ((i = $(files_state | jq .placeAt); i < at; i++)); do wtype j; done
wtype -k Return
until_ok 3000 files_is --arg d "$drive" '.listed and .folder == $d'
wtype p
until_ok 8000 files_is '.op.card != null'
check "a failure with 30 files keeps the card inside the window ($(files_state | jq -c '.op.card | {fits, title}'))" files_is '.op.card.fits and .op.card.title == "FULLDRIVE is full"'
wtype -k Escape
until_ok 5000 files_is '.op.running == false'
close_files

errs=$(grep -E 'TypeError|ReferenceError|SyntaxError|Failed to load|is not a type|Cannot assign|Unable to assign|Cannot read propert|unavailable' "$log")
check "Files' log has no QML errors${errs:+: $(head -c 200 <<<"$errs")}" test -z "$errs"

exit $((fails > 0))
}
