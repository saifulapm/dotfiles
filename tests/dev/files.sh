#!/usr/bin/env bash
# Files is an App: Mod+Y starts its own qs process with one window in the theme, a second Mod+Y focuses it, and Esc ends the process.
{
source "$(dirname "$0")/lib.sh"

files_qml=$repo/shell/files.qml
work=$(mktemp -d)
cleanup() { rm -rf "$work"; }
mkdir -p "$work/home/Downloads/screenshots"
log=$work/files.log

files_state() { timeout 0.5 qs ipc -p "$files_qml" call files state 2>/dev/null; }
files_is() { files_state | jq -e "$1" >/dev/null 2>&1; }
files_windows() { niri msg -j windows | jq '[.[] | select(.app_id == "files")] | length'; }
files_up() { [ "$(files_windows)" = 1 ] && files_is '.firstFrameMs != null'; }
files_gone() { [ "$(files_windows)" = 0 ]; }
# The App's own qs, found by its command line, never by pgrep -f, which matches this shell too.
files_pids() {
  local pid
  for pid in $(pgrep -x qs); do
    tr '\0' ' ' <"/proc/$pid/cmdline" | grep -qF -- "-p $files_qml" && echo "$pid"
  done
  return 0
}
no_files_process() { [ -z "$(files_pids)" ]; }
# niri runs no binds for wtype's virtual keyboard, so the check spawns the bind's command, dots-files, through niri.
mod_y() { niri msg action spawn -- sh -c "HOME='$work/home' exec dots-files 2>>'$log'"; }

mod_y
until_ok 5000 files_up
check "Mod+Y opens one window whose app id is files ($(files_windows))" files_up
check "its first frame came $(files_state | jq .firstFrameMs) ms after the process started, under 500" \
  files_is '(.firstFrameMs | type) == "number" and .firstFrameMs > 0 and .firstFrameMs < 500'
check "its title is the folder, Home ($(niri msg -j windows | jq -r '.[] | select(.app_id == "files") | .title'))" \
  bash -c "niri msg -j windows | jq -e 'any(.[]; .app_id == \"files\" and .title == \"Home\")' >/dev/null"
check "the header reads FILES · Home · MOD Y in Paper ($(files_state | jq -c .head))" \
  files_is '.head == {"label": "FILES", "folder": "Home", "chip": "MOD Y"}'

niri msg action spawn -- foot -c /dev/null
until_ok 3000 bash -c "niri msg -j windows | jq -e 'any(.[]; .app_id == \"foot\" and .is_focused)' >/dev/null"
pid=$(files_pids)
mod_y
files_focused() { niri msg -j windows | jq -e 'any(.[]; .app_id == "files" and .is_focused)' >/dev/null; }
until_ok 3000 files_focused
check "a second Mod+Y focuses the open window and starts no second process" \
  bash -c "[ \"\$(niri msg -j windows | jq '[.[] | select(.app_id == \"files\")] | length')\" = 1 ] && [ '$(files_pids)' = '$pid' ]"

wtype -k Escape
until_ok 3000 files_gone
check "Esc closes the window" files_gone
until_ok 3000 no_files_process
check "and its process exits" no_files_process

mod_y
until_ok 5000 files_up
niri msg action close-window
until_ok 3000 no_files_process
check "closing the window from niri ends the process too" no_files_process

errs=$(grep -E 'TypeError|ReferenceError|SyntaxError|Failed to load|is not a type|Cannot assign|Unable to assign|Cannot read propert|unavailable' "$log")
check "Files' log has no QML errors${errs:+: $(head -c 200 <<<"$errs")}" test -z "$errs"

exit $((fails > 0))
}
