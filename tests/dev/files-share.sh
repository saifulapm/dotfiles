#!/usr/bin/env bash
# In Files, s lists the tailnet's devices, online first and offline dimmed; Enter on an online one sends the marked files through dots-taildrop-send, closes the list and leaves the progress to the island, Enter on an offline one does nothing, and Esc gives the keys back.
{
source "$(dirname "$0")/lib.sh"

files_qml=$repo/shell/files.qml
ts_dir=$DOTS_DEV_DIR/tailscale
work=$(mktemp -d)
h=$work/home
log=$work/files.log
mkdir -p "$h/.config/gtk-3.0"
# Sparse files that add up to 8.9 MB, the size the boards draw.
truncate -s 4000000 "$h/a.bin"
truncate -s 3000000 "$h/b.bin"
truncate -s 1900000 "$h/c.bin"
# The fake's peers are seeded before Files reads them, and put back after: the iPhone is named with a capital as the board writes it, and one more online device has a newline and U+202E in its name.
"$repo/dev/path/tailscale" status --json >/dev/null
cp "$ts_dir/status.json" "$work/status.json"
cleanup() {
  cp "$work/status.json" "$ts_dir/status.json"
  rm -f "$ts_dir/cp.log"
  niri msg action close-window >/dev/null 2>&1
  rm -rf "$work"
}
forged=$(printf 'a\nb\xe2\x80\xaec')
jq --arg f "$forged" '(.Peer[] | select(.DNSName | startswith("iphone.")) | .DNSName) = "iPhone.taila27604.ts.net."
  | .Peer.forged = ((.Peer | to_entries | map(select(.value.DNSName | startswith("nuc."))) | .[0].value) | .DNSName = ($f + ".taila27604.ts.net.") | .HostName = "x")' \
  "$work/status.json" >"$ts_dir/status.json"
rm -f "$ts_dir/cp.log"

files_state() { timeout 0.5 qs ipc -p "$files_qml" call files state 2>/dev/null; }
files_is() { files_state | jq -e "$@" >/dev/null 2>&1; }
island() { timeout 0.5 qs ipc call island state 2>/dev/null; }
island_is() { island | jq -e "$@" >/dev/null 2>&1; }
files_windows() { niri msg -j windows | jq '[.[] | select(.app_id == "files")] | length'; }
files_up() { [ "$(files_windows)" = 1 ] && files_is '.firstFrameMs != null and .listed'; }
status_theme() { shell_status | jq -e --arg t "$1" '.theme == $t' >/dev/null; }
no_transition() { shell_status | jq -e '.transition == ""' >/dev/null; }
in_theme() { "$repo/bin/dots" theme "$1" >/dev/null; until_ok 2000 status_theme "$1"; until_ok 2000 no_transition; sleep 0.3; }
open_share() { wtype s; until_ok 3000 files_is '.share.open and .share.listed and (.share.rows | length) > 0'; }
close_share() { wtype -k Escape; until_ok 2000 files_is '.share.open == false'; }
# Moves the list's cursor to the first row whose name starts with $1.
share_to() {
  local i
  for i in 1 2 3 4 5 6 7; do
    files_is --arg n "$1" '.share.rows[.share.selected].name | startswith($n)' && return 0
    wtype j
    sleep 0.15
  done
  return 1
}
cp_log() { cat "$ts_dir/cp.log" 2>/dev/null; }

niri msg action spawn -- sh -c "HOME='$h' XDG_CONFIG_HOME='$h/.config' exec dots-files 2>>'$log'"
until_ok 5000 files_up
in_theme paper
wtype -k space -k space -k space
until_ok 1000 files_is '(.marked | length) == 3'
check "three files are marked ($(files_state | jq -c .marked))" files_is '.marked == ["a.bin", "b.bin", "c.bin"]'

open_share
echo "     share: $(files_state | jq -c '.share | {head, rows: [.rows[] | [.name, .detail, .status, .color]]}')"
check "s lists the devices over Files: 6 rows" files_is '.share.open and (.share.rows | length) == 6'
check "online devices come first, offline ones after" files_is '(.share.rows | map(.status == "offline")) as $o | $o == ($o | sort) and ($o | any) and ($o | all | not)'
check "an offline row is drawn in Paper's muted #575653, an online one in its ink #1c1915" \
  files_is '(.share.rows | map(select(.status == "offline" and (.current | not)) | .color) | unique) == ["#575653"] and .share.rows[1].status == "online" and .share.rows[1].color == "#1c1915"'
check "a device named with a newline and U+202E draws on one line, without them ($(files_state | jq -c '.share.rows[0] | [.name, .lines]'))" \
  files_is '.share.rows[0].lines == 1 and (.share.rows[0].name | test("[\\n‮]") | not) and (.share.rows[0].name | startswith("a b"))'

share_to fedora
check "the cursor is on fedora, offline ($(files_state | jq -c '.share.rows[.share.selected] | [.name, .status]'))" files_is '.share.rows[.share.selected] | .name == "fedora" and .status == "offline"'
wtype -k Return
sleep 1
check "Enter on fedora keeps the list open" files_is '.share.open'
check "and sends nothing: no file cp, no dots-taildrop-send, no sending island" bash -c "[ ! -e '$ts_dir/cp.log' ] && ! pgrep -f '[d]ots-taildrop-send' >/dev/null && ! timeout 0.5 qs ipc call island state | jq -e '.mode == \"sending\"' >/dev/null"

close_share
check "Esc closes the list and Files stays open with its marks ($(files_windows) window)" files_is '.share.open == false and (.marked | length) == 3 and .folder == "'"$h"'"'
wtype k
until_ok 1000 files_is '.selected == 1'
check "the keys are Files' again: k moved the cursor" files_is '.cursor == "b.bin"'

open_share
share_to iPhone
check "the cursor is on the iPhone, online" files_is '.share.rows[.share.selected] | .name == "iPhone" and .status == "online"'
wtype -k Return
check "Enter on the iPhone closes the list" until_ok 2000 files_is '.share.open == false'
check "and the island shows the send of 3 files to iPhone ($(island | jq -c .sending))" until_ok 5000 island_is '.mode == "sending" and .sending.label == "SENDING 3 FILES TO IPHONE ·"'
check "the fake logged one file cp of the three paths to the iPhone's address ($(cp_log))" \
  test "$(cp_log)" = "file cp $h/a.bin $h/b.bin $h/c.bin 100.95.3.21:"
check "the send ends and the island lets go of it" until_ok 15000 island_is '.sending == null'

for theme in paper artboard blueprint; do
  in_theme "$theme"
  open_share
  echo "     $theme: $(files_state | jq -c '.share | {head, keys, first: .rows[1]}')"
  case $theme in
    paper) head='{"label": "SHARE", "count": "3 files · 8.9 MB", "tag": "tailnet"}' keys='["↵ SEND WITH TAILDROP", "J/K MOVE", "ESC"]' on=online off='offline, seen' ;;
    artboard) head='{"label": "Share", "count": "3 files · 8.9 MB", "tag": "tailnet"}' keys='["↵ send with Taildrop", "j/k move", "esc"]' on=online off='offline, seen' ;;
    blueprint) head='{"label": "SHARE", "count": "3 FILES · 8.9 MB", "tag": "TAILNET"}' keys='["[↵] SEND WITH TAILDROP", "[J/K] MOVE", "[ESC]"]' on=ONLINE off='OFFLINE, SEEN' ;;
  esac
  check "$theme: the head reads as its board does" files_is --argjson h "$head" '.share.head == $h'
  check "$theme: the key strip reads as its board does" files_is --argjson k "$keys" '.share.keys == $k'
  check "$theme: an online row reads its address and $on" files_is --arg on "$on" '.share.rows[] | select(.name == "iPhone") | .detail == "100.95.3.21" and .status == $on'
  check "$theme: an offline row reads when it was seen" files_is --arg off "$off" '.share.rows[] | select(.name == "fedora") | (.detail | startswith($off))'
  close_share
done

errs=$(grep -E 'TypeError|ReferenceError|SyntaxError|Failed to load|is not a type|Cannot assign|Unable to assign|Cannot read propert|unavailable' "$log")
check "Files' log has no QML errors${errs:+: $(head -c 300 <<<"$errs")}" test -z "$errs"

exit $((fails > 0))
}
