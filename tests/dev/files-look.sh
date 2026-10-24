#!/usr/bin/env bash
# Files draws as its boards do in Paper, Artboard and Blueprint: each row's mark and icon, the date's face, the key strip's case, the path line's parts, the current place's fill, and no preview in a narrow window; every field is read back from the drawn item.
{
source "$(dirname "$0")/lib.sh"

files_qml=$repo/shell/files.qml
work=$(mktemp -d)
cleanup() { rm -rf "$work"; }
h=$work/home
mkdir -p "$h/Downloads/screenshots/old" "$h/Downloads/taildrop" "$h/Codes" "$h/Pictures" "$h/Documents" "$h/.config/gtk-3.0"
for i in 1 2 3 4 5 6 7; do : >"$h/Downloads/screenshots/shot-$i.png"; done
for n in IMG_2039.jpg IMG_2040.jpg IMG_2041.jpg invoice-0912.pdf notes.txt; do : >"$h/Downloads/$n"; done
printf 'file://%s/Codes lareys\nfile://%s/Documents invoices\n' "$h" "$h" >"$h/.config/gtk-3.0/bookmarks"
log=$work/files.log

files_state() { timeout 0.5 qs ipc -p "$files_qml" call files state 2>/dev/null; }
files_is() { files_state | jq -e "$@" >/dev/null 2>&1; }
json_is() { jq -e "$@" >/dev/null; }
files_call() { timeout 0.5 qs ipc -p "$files_qml" call files "$@" 2>/dev/null; }
status_theme() { shell_status | jq -e --arg t "$1" '.theme == $t' >/dev/null; }
in_theme() { "$repo/bin/dots" theme "$1" >/dev/null; until_ok 2000 status_theme "$1"; }
files_focused() { niri msg -j windows | jq -e 'any(.[]; .app_id == "files" and .is_focused)' >/dev/null; }
files_gone() { ! niri msg -j windows | jq -e 'any(.[]; .app_id == "files")' >/dev/null; }

# The boards' paths: Paper and Blueprint share a set, Artboard rounds its own.
folder_sharp='M1.8 4.2h4l1.4 1.6h7v6.6H1.8z'
file_sharp='M3.5 1.8h6l3 3v9.4h-9z M9.5 1.8v3h3'
folder_round='M2 4.5A1.5 1.5 0 0 1 3.5 3H6l1.5 1.8h5A1.5 1.5 0 0 1 14 6.3v5.2a1.5 1.5 0 0 1-1.5 1.5h-9A1.5 1.5 0 0 1 2 11.5z'
file_round='M4 1.8h5l3 3V13a1.2 1.2 0 0 1-1.2 1.2H4A1.2 1.2 0 0 1 2.8 13V3A1.2 1.2 0 0 1 4 1.8zM9 1.8V5h3'

# theme | marked mark | its fill | unmarked mark | folder icon | file icon | date face,italic,size | first key | its word | key weight | current place fill | lead colour
for t in "paper|■|#1c1915|□|$folder_sharp|$file_sharp|Instrument Serif,true,17|J/K|MOVE|700|#f1e9d8|#575653" \
  "artboard|●|#3d5afe|○|$folder_round|$file_round|Maple Mono,false,12|j/k|move|500|#eef1ff|#57606a" \
  "blueprint|■|#7fe3f0|□|$folder_sharp|$file_sharp|Maple Mono,false,12|[J/K]|MOVE|700|#1a7fe3f0|#80a4c2"; do
  IFS='|' read -r name on onfill off folder file date key word weight here lead <<<"$t"
  in_theme "$name"
  niri msg action spawn -- sh -c "HOME='$h' XDG_CONFIG_HOME='$h/.config' exec dots-files >>'$log' 2>&1"
  until_ok 5000 files_is '.listed and .firstFrameMs != null'
  until_ok 3000 files_focused
  wtype jj
  until_ok 1000 files_is '.cursor == "Downloads"'
  wtype l
  until_ok 2000 files_is '.listed and (.folder | endswith("/Downloads"))'
  wtype jj
  until_ok 1000 files_is '.cursor == "IMG_2039.jpg"'
  wtype -k space
  until_ok 1000 files_is '.marked == ["IMG_2039.jpg"] and .cursor == "IMG_2040.jpg"'

  marked=$(files_call row IMG_2039.jpg)
  plain_row=$(files_call row invoice-0912.pdf)
  folder_row=$(files_call row screenshots)
  check "$name: a marked row draws $on${onfill:+ filled $onfill} ($(jq -c '{mark, markFill}' <<<"$marked"))" \
    json_is --arg m "$on" --arg f "$onfill" '.mark == $m and ($f == "" or .markFill == $f)' <<<"$marked"
  check "$name: an unmarked row draws $off ($(jq -c '{mark, markFill}' <<<"$plain_row"))" json_is --arg m "$off" '.mark == $m' <<<"$plain_row"
  check "$name: a folder row draws the board's folder and a file row its page ($(jq -c .icon <<<"$folder_row") $(jq -c .icon <<<"$plain_row"))" \
    bash -c 'jq -e --arg p "$1" ".icon == \$p" <<<"$2" >/dev/null && jq -e --arg p "$3" ".icon == \$p" <<<"$4" >/dev/null' _ "$folder" "$folder_row" "$file" "$plain_row"
  check "$name: MODIFIED draws in $date ($(jq -c .dateFont <<<"$plain_row"))" \
    json_is --arg d "$date" '([.dateFont.family, (.dateFont.italic | tostring), (.dateFont.size | tostring)] | join(",")) == $d' <<<"$plain_row"
  check "$name: the key strip starts '$key $word', the key at weight $weight ($(files_state | jq -c .strip))" \
    files_is --arg k "$key" --arg w "$word" --argjson n "$weight" '.strip.key == $k and .strip.word == $w and .strip.keyWeight == $n'
  check "$name: the path line is the folder icon, a muted ~/ and Downloads at weight 500 ($(files_state | jq -c .pathParts))" \
    files_is --arg i "$folder" --arg c "$lead" '.pathParts == {"icon": $i, "lead": "~/", "leadColor": $c, "name": "Downloads", "nameWeight": 500}'
  place_here=$(files_call place Downloads)
  place_off=$(files_call place Home)
  check "$name: the current place is filled $here, another place is not ($place_here $(jq -c .fill <<<"$place_off"))" \
    bash -c 'jq -e --arg f "$1" ".fill == \$f" <<<"$2" >/dev/null && jq -e ".fill == \"#00000000\"" <<<"$3" >/dev/null' _ "$here" "$place_here" "$place_off"

  check "$name: the preview shows in the full window ($(files_state | jq -c '{width, shown: .preview.shown}'))" files_is '.preview.shown'
  # FilesMarked draws the narrow layout 850 px wide, with no preview.
  niri msg action set-window-width 840
  check "$name: a window narrower than the board's 850 px hides the preview ($(until_ok 2000 files_is '.width < 850'; files_state | jq -c '{width, shown: .preview.shown}'))" \
    files_is '(.width | type) == "number" and .width < 850 and .preview.shown == false'
  wtype -k Escape
  until_ok 3000 files_gone
done
in_theme paper

errs=$(grep -E 'TypeError|ReferenceError|SyntaxError|Failed to load|is not a type|Cannot assign|Unable to assign|Cannot read propert|unavailable' "$log")
check "Files' log has no QML errors${errs:+: $(head -c 200 <<<"$errs")}" test -z "$errs"

exit $((fails > 0))
}
