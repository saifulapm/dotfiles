#!/usr/bin/env bash
# Files' Open with: o on three marked JPEGs lists the apps that declare image/jpeg with the default first, Enter opens all three in one launch, shift+Enter makes the app the default through a symlinked mimeapps.list, and Esc gives the keys back to the rows.
{
source "$(dirname "$0")/lib.sh"

files_qml=$repo/shell/files.qml
work=$(mktemp -d)
cleanup() { rm -rf "$work"; }
h=$work/home
mkdir -p "$h/Downloads" "$h/.config" "$work/dotfiles"
for n in a b c; do cp /usr/share/doc/lynx/test/image.jpg "$h/Downloads/$n.jpg"; done
# As on Saiful's machines, mimeapps.list is a link into the dotfiles; Files' XDG_CONFIG_HOME is the scratch one, so shift+Enter never writes the real default.
printf '[Default Applications]\nimage/jpeg=imv.desktop\n' >"$work/dotfiles/mimeapps.list"
ln -s "$work/dotfiles/mimeapps.list" "$h/.config/mimeapps.list"
apps=$DOTS_DEV_DIR/data/applications
printf '#!/bin/sh\nprintf "%%s\\n" "launch $#" "$@" >>"%s"\n' "$work/args" >"$work/viewer"
chmod +x "$work/viewer"
printf '[Desktop Entry]\nType=Application\nName=Test viewer\nExec=%s %%F\nMimeType=image/jpeg;\n' "$work/viewer" >"$apps/dots-test-viewer.desktop"
# A desktop entry's \n is a newline once read; U+202E is written as is.
printf '[Desktop Entry]\nType=Application\nName=zz forged\\nname\xe2\x80\xaex\nExec=true %%F\nMimeType=image/jpeg;\n' >"$apps/dots-test-forged.desktop"
# Gio finds an entry's types in the folder's mimeinfo.cache, not in the entry.
update-desktop-database "$apps"
log=$work/files.log
in_files_env() { env XDG_CONFIG_HOME="$h/.config" XDG_DATA_HOME="$DOTS_DEV_DIR/data" "$@"; }

files_state() { timeout 0.5 qs ipc -p "$files_qml" call files state 2>/dev/null; }
files_is() { files_state | jq -e "$@" >/dev/null 2>&1; }
files_up() { files_is '.firstFrameMs != null'; }
files_gone() { [ "$(niri msg -j windows | jq '[.[] | select(.app_id == "files")] | length')" = 0 ]; }
mod_y() { niri msg action spawn -- sh -c "HOME='$h' XDG_CONFIG_HOME='$h/.config' exec dots-files 2>>'$log'"; }
ow() { files_state | jq -c ".openWith$1"; }
# Moves the list's cursor to the app with this desktop id.
to_app() {
  local at by
  at=$(files_state | jq --arg a "$1" '.openWith.rows | map(.app) | index($a)')
  by=$((at - $(files_state | jq .openWith.at)))
  for ((; by > 0; by--)); do wtype j; done
  until_ok 1000 files_is --argjson n "$at" '.openWith.at == $n'
}
listed_apps() { files_is '.openWith.open and (.openWith.rows | length) > 0'; }

mod_y
until_ok 5000 files_up
until_ok 2000 files_is '.listed and .cursor == "Downloads"'
wtype l
until_ok 2000 files_is '.listed and (.folder | endswith("/Downloads"))'
wtype -k space -k space -k space
until_ok 1000 files_is '(.marked | length) == 3'

wtype o
until_ok 3000 listed_apps
registered=$(in_files_env gio mime image/jpeg | sed -n '/^Registered/,/^Recommended/{s/^\t//p}' | jq -Rsc 'split("\n") | map(select(. != "")) | sort')
check "o lists the apps that declare image/jpeg ($(ow '.rows | map(.app)'))" \
  files_is --argjson r "$registered" '(.openWith.rows | map(.app) | sort) == $r and ($r | index("chromium-browser.desktop")) and ($r | index("dots-test-viewer.desktop"))'
check "imv is first, drawn as the default ($(ow '.rows[0]'))" files_is '.openWith.rows[0] | .app == "imv.desktop" and .name == "imv" and .badge == "default"'
check "only the default draws a badge" files_is '[.openWith.rows[1:][] | .badge] | all(. == "")'
check "a Name with a newline and U+202E draws on one line ($(ow '.rows[] | select(.app == "dots-test-forged.desktop") | {name, lines}'))" \
  files_is '.openWith.rows[] | select(.app == "dots-test-forged.desktop") | .lines == 1 and .name == "zz forged namex"'

n=$(files_state | jq '.openWith.rows | length')
status_theme() { shell_status | jq -e --arg t "$1" '.theme == $t' >/dev/null; }
in_theme() { "$repo/bin/dots" theme "$1" >/dev/null && until_ok 2000 status_theme "$1" && until_ok 2000 files_is --arg v "$2" '.voice == $v'; }
in_theme paper caps
check "Paper: OPEN WITH · 3 JPEG images · $n apps ($(ow '| {label, title, count}'))" \
  files_is --arg c "$n apps" '.openWith | .label == "OPEN WITH" and .title == "3 JPEG images" and .count == $c'
check "Paper: the keys read ↵ OPEN, J/K MOVE, SHIFT+↵ MAKE DEFAULT, ESC ($(ow .keys))" \
  files_is '.openWith.keys == [{"key": "↵", "word": "OPEN"}, {"key": "J/K", "word": "MOVE"}, {"key": "SHIFT+↵", "word": "MAKE DEFAULT"}, {"key": "ESC", "word": ""}]'
check "Paper: imv's row reads Image viewer · imv, default ($(ow '.rows[0] | {sub, badge}'))" files_is '.openWith.rows[0] | .sub == "Image viewer · imv" and .badge == "default"'
in_theme artboard plain
check "Artboard: Open with · 3 JPEG images · $n apps ($(ow '| {label, title, count}'))" \
  files_is --arg c "$n apps" '.openWith | .label == "Open with" and .title == "3 JPEG images" and .count == $c'
check "Artboard: the keys read as typed ($(ow .keys))" \
  files_is '.openWith.keys == [{"key": "↵", "word": "open"}, {"key": "j/k", "word": "move"}, {"key": "shift+↵", "word": "make default"}, {"key": "esc", "word": ""}]'
check "Artboard: imv's row reads Image viewer · imv, default" files_is '.openWith.rows[0] | .sub == "Image viewer · imv" and .badge == "default"'
in_theme blueprint bracket
check "Blueprint: OPEN WITH // 3 JPEG IMAGES · $n APPS ($(ow '| {label, title, count}'))" \
  files_is --arg c "$n APPS" '.openWith | .label == "OPEN WITH" and .title == "3 JPEG IMAGES" and .count == $c'
check "Blueprint: the keys are bracketed in caps ($(ow .keys))" \
  files_is '.openWith.keys == [{"key": "[↵]", "word": "OPEN"}, {"key": "[J/K]", "word": "MOVE"}, {"key": "[SHIFT+↵]", "word": "MAKE DEFAULT"}, {"key": "[ESC]", "word": ""}]'
check "Blueprint: imv's row reads IMAGE VIEWER · imv, [DEFAULT] ($(ow '.rows[0] | {sub, badge}'))" files_is '.openWith.rows[0] | .sub == "IMAGE VIEWER · imv" and .badge == "[DEFAULT]"'
in_theme paper caps

wtype -k Escape
until_ok 1000 files_is '.openWith.open | not'
check "Esc closes the list and leaves Files open with the marks kept" files_is '(.openWith.open | not) and (.marked | length) == 3'
wtype k
until_ok 1000 files_is '.cursor == "b.jpg"'
check "and the keys are the rows' again: k moves the cursor to b.jpg ($(files_state | jq -r .cursor))" files_is '.cursor == "b.jpg"'

wtype o
until_ok 3000 listed_apps
to_app dots-test-viewer.desktop
wtype -k Return
d=$h/Downloads
args_are() { [ "$(cat "$work/args" 2>/dev/null)" = "$(printf 'launch 3\n%s\n%s\n%s' "$d/a.jpg" "$d/b.jpg" "$d/c.jpg")" ]; }
until_ok 3000 args_are
check "Enter on the test viewer opens all three in one launch ($(tr '\n' ' ' <"$work/args"))" args_are
check "and closes the list" files_is '.openWith.open | not'

files_id=$(niri msg -j windows | jq '.[] | select(.app_id == "files") | .id')
imv_up() { niri msg -j windows | jq -e 'any(.[]; .app_id == "imv")' >/dev/null; }
wtype o
until_ok 3000 listed_apps
wtype -k Return
until_ok 5000 imv_up
check "Enter on imv opens its window" imv_up
niri msg action close-window --id "$(niri msg -j windows | jq '.[] | select(.app_id == "imv") | .id')"
until_ok 3000 bash -c "! niri msg -j windows | jq -e 'any(.[]; .app_id == \"imv\")' >/dev/null"
niri msg action focus-window --id "$files_id"

default_is() { [ "$(in_files_env xdg-mime query default image/jpeg)" = "$1" ]; }
wtype o
until_ok 3000 listed_apps
to_app chromium-browser.desktop
wtype -M shift -k Return -m shift
until_ok 3000 default_is chromium-browser.desktop
check "shift+Enter on Chromium makes it the default ($(in_files_env xdg-mime query default image/jpeg))" default_is chromium-browser.desktop
check "the scratch mimeapps.list is still a link ($(stat -c %F "$h/.config/mimeapps.list"))" test -L "$h/.config/mimeapps.list"
check "its target holds the new line ($(tr '\n' ' ' <"$work/dotfiles/mimeapps.list"))" \
  test "$(cat "$work/dotfiles/mimeapps.list")" = "$(printf '[Default Applications]\nimage/jpeg=chromium-browser.desktop')"
until_ok 3000 files_is '.openWith.rows[0].app == "chromium-browser.desktop"'
check "the list puts Chromium first with the badge ($(ow '.rows[0] | {app, badge}'))" files_is '.openWith.open and (.openWith.rows[0] | .app == "chromium-browser.desktop" and .badge == "default")'

wtype -k Escape
until_ok 1000 files_is '.openWith.open | not'
wtype -k Escape
until_ok 3000 files_gone
check "a second Esc closes Files" files_gone

errs=$(grep -E 'TypeError|ReferenceError|SyntaxError|Failed to load|is not a type|Cannot assign|Unable to assign|Cannot read propert|unavailable' "$log")
check "Files' log has no QML errors${errs:+: $(head -c 200 <<<"$errs")}" test -z "$errs"

exit $((fails > 0))
}
