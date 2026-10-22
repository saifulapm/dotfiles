#!/usr/bin/env bash
# The picker in each theme's idiom: the preview's meta lines with the size read from the image's header, the heading chips, the folder and save path rows, the several-files key strip, and a heading that never pushes the query out of the card.
{
source "$(dirname "$0")/lib.sh"

sock=$XDG_RUNTIME_DIR/dots-picker-$WAYLAND_DISPLAY.sock
look=$DOTS_DEV_DIR/look out=$DOTS_DEV_DIR/answers
mkdir -p "$look/shots" "$look/pick/Codes" "$look/pick/music" "$look/save/drafts" "$out"
# A 1600 x 1200 PNG, past the 1024 px bound Qt decodes it at.
python3 -c '
import struct, sys, zlib
w, h = 1600, 1200
raw = b"".join(b"\0" + b"\x30\x60\x90" * w for _ in range(h))
ch = lambda t, d: struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d))
open(sys.argv[1], "wb").write(b"\x89PNG\r\n\x1a\n" + ch(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)) + ch(b"IDAT", zlib.compress(raw)) + ch(b"IEND", b""))
' "$look/shots/Wide-Shot.png"
ffmpeg -loglevel error -y -f lavfi -i color=c=0x306090:s=640x480 -frames:v 1 "$look/shots/Photo.jpg"
truncate -s 184000 "$look/shots/Report.pdf"
for n in IMG_2039.HEIC IMG_2040.HEIC IMG_2041.HEIC; do truncate -s 2800000 "$look/shots/$n"; done
: >"$look/pick/notes.txt"
: >"$look/save/notes.md"
: >"$look/save/report.pdf"

pk_state() { timeout 0.5 dots-call picker state 2>/dev/null; }
state_is() { pk_state | jq -e "$@" >/dev/null 2>&1; }
request() { jq -cn --arg mode "$1" --arg folder "$2" --argjson multiple "${3-false}" --arg app "${4-chromium-browser}" '{mode: $mode, multiple: $multiple, title: "", app: $app, folder: $folder, name: (if $mode == "save" then "report.pdf" else "" end), filters: [], filter: 0, accept: ""}'; }
ask() {
  rm -f "$out/$1"
  node -e '
    const [sock, line, file] = process.argv.slice(1), chunks = [];
    const s = require("net").connect(sock, () => s.write(line + "\n"));
    s.on("data", (d) => chunks.push(d));
    s.on("close", () => require("fs").writeFileSync(file, Buffer.concat(chunks)));
  ' "$sock" "$2" "$out/$1" &
}
answered() { [ -e "$out/$1" ]; }
shown() { until_ok 4000 state_is '.open and .settled and .listed'; }
cancel() { wtype -k Escape; until_ok 3000 answered "$1"; }
cursor_to() {
  local i
  for i in 1 2 3 4 5 6 7 8; do
    until_ok 300 state_is --arg n "$1" '.rows[.selected].name == $n' && return 0
    wtype -k Down
  done
  return 1
}
mark() { wtype -M ctrl -k space -m ctrl; }
preview_of() { pk_state | jq -c '{previewName, preview, previewHead, previewBadge, previewLines}'; }
# Every drawn box lies inside the card.
inside='. as $s | [.boxes[] | select(. != null)] | all(.x >= 0 and .y >= 0 and .x + .width <= $s.cardSize[0] + 0.5 and .y + .height <= $s.cardSize[1] + 0.5)'
# A row's drawn mark, name colour, the colour under it and their WCAG contrast, from theme.mjs.
row_look() {
  pk_state | node --input-type=module -e '
    const { contrast } = await import(process.argv[1] + "/shell/lib/theme.mjs");
    const { readFileSync } = await import("node:fs");
    const r = JSON.parse(readFileSync(0, "utf8")).rows.find((r) => r.name === process.argv[2]);
    console.log(JSON.stringify(r ? { mark: r.mark, ink: r.ink, behind: r.behind, contrast: Number(contrast(r.ink, r.behind).toFixed(2)) } : null));
  ' "$repo" "$1"
}
ratio_at_least() { row_look "$2" | jq -e --argjson min "$1" '.contrast >= $min' >/dev/null; }
long=$(printf 'chrome-%0193d' 0)

status_theme() { shell_status | jq -e --arg t "$1" '.theme == $t' >/dev/null; }
in_theme() { "$repo/bin/dots" theme "$1" >/dev/null; until_ok 2000 status_theme "$1"; }
iso='^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}$'
dotted='^[0-9]{1,2} [A-Z][a-z]{2} [0-9]{4} · [0-9]{2}:[0-9]{2}$'
comma='^[0-9]{1,2} [A-Z][a-z]{2} [0-9]{4}, [0-9]{2}:[0-9]{2}$'
for t in "paper|DIMENSIONS,SIZE,MODIFIED|1600 × 1200|640 × 480|||$dotted|3 MARKED|FOLDERS ONLY|2 FOLDERS · FILES HIDDEN|NAME,ITEMS,MODIFIED|↵ OPEN · TAB PLACES · ⌃L PATH · ⌃H HIDDEN · ⌃␣ MARK · ESC|SAVE IN|3 ITEMS|1 PLACE|✓|" \
  "artboard|,,|1600 × 1200 px|640 × 480 px||PNG|$comma|3 marked|folders only|2 folders · files hidden|Name ↑,Items,Modified|↵ open · tab places · ctrl+l path · ctrl+h hidden · ctrl+space select · esc||3 items|→ Downloads|✓|" \
  "blueprint|DIMENSIONS,SIZE,MODIFIED|1600 × 1200|640 × 480|PREVIEW IMAGE||$iso|3 MARKED|FOLDERS ONLY|2 FOLDERS · FILES HIDDEN|NAME,ITEMS,MODIFIED|[↵] OPEN · [TAB] PLACES · [⌃L] PATH · [⌃H] HIDDEN · [⌃␣] SELECT · [ESC]|> FOLDER|3 ITEMS|1 PLACE|[x]|[ ]"; do
  IFS='|' read -r name labels png jpg head badge date marked only folders heads strip lead items match on off <<<"$t"
  in_theme "$name"

  # The preview: the header's size, not the bounded one Qt decoded, in the theme's labels; no dimensions for a PDF.
  ask "preview-$name" "$(request open "$look/shots")"
  shown
  cursor_to Photo.jpg
  check "$name: a 640 x 480 JPEG draws $jpg ($(until_ok 3000 state_is '.previewDims != ""'; preview_of))" state_is --arg d "$jpg" '.previewDims == $d and .previewName == "Photo.jpg"'
  cursor_to Report.pdf
  check "$name: a PDF draws no dimensions line and no picture ($(until_ok 2000 state_is '.previewName == "Report.pdf"'; preview_of))" until_ok 2000 state_is '.previewName == "Report.pdf" and .preview == false and .previewDims == "" and (.previewLines | length) == 2 and .previewLines[0].value == "184 KB"'
  [ "$name" = blueprint ] && check "blueprint: the PDF's head reads PREVIEW FILE" state_is '.previewHead == "PREVIEW FILE"'
  [ "$name" = artboard ] && check "artboard: the PDF's badge reads PDF" state_is '.previewBadge == "PDF"'

  cursor_to Wide-Shot.png
  until_ok 3000 state_is '.preview and .previewDims != ""'
  check "$name: a 1600 x 1200 PNG draws $png ($(preview_of))" state_is --arg d "$png" '.preview and .previewDims == $d and .previewLines[0].value == $d'
  check "$name: its lines are labelled '$labels', the name in real case" state_is --arg l "$labels" '([.previewLines[].label] | join(",")) == $l and .previewName == "Wide-Shot.png"'
  check "$name: the date reads in the theme's form" state_is --arg r "$date" '.previewLines[2].value | test($r)'
  check "$name: the head reads '$head' and the badge '$badge'" state_is --arg h "$head" --arg b "$badge" '.previewHead == $h and .previewBadge == $b'
  [ "$name" = paper ] && check "paper: the name is set in the serif at 24 px ($(pk_state | jq -c .previewNameFont))" state_is '.previewNameFont[1] == 24'

  # Several files: the marked chip and the key strip.
  wtype -k Escape
  until_ok 3000 answered "preview-$name"
  ask "multi-$name" "$(request open "$look/shots" true)"
  shown
  check "$name: a several-files request keys $strip ($(pk_state | jq -c .hint))" state_is --arg s "$strip" '.hint == $s'
  check "$name: and no chip while nothing is marked" state_is '.chip == ""'
  for n in IMG_2039.HEIC IMG_2040.HEIC IMG_2041.HEIC; do
    cursor_to "$n"
    mark
  done
  check "$name: three marked files chip the heading $marked ($(pk_state | jq -c '[.chip, .marked]'))" until_ok 1000 state_is --arg c "$marked" '.chip == $c'
  # IMG_2039 is marked and off the cursor, Photo.jpg is an unmarked file.
  check "$name: a marked row off the cursor draws its name at contrast 4.5 or more ($(row_look IMG_2039.HEIC))" ratio_at_least 4.5 IMG_2039.HEIC
  check "$name: a marked file draws '$on' and an unmarked one '$off' ($(row_look IMG_2039.HEIC) $(row_look Photo.jpg))" state_is --arg on "$on" --arg off "$off" '(.rows[] | select(.name == "IMG_2039.HEIC") | .mark) == $on and (.rows[] | select(.name == "Photo.jpg") | .mark) == $off'
  cancel "multi-$name"

  # A folder request: its chip, the path row's count and the Items head.
  ask "folder-$name" "$(request folder "$look/pick")"
  shown
  check "$name: a folder request chips the heading $only, counts $folders, heads $heads ($(pk_state | jq -c '[.chip, .count, .heads]'))" state_is --arg c "$only" --arg n "$folders" --arg h "$heads" '.chip == $c and .count == $n and (.heads | join(",")) == $h'
  cancel "folder-$name"

  # Save: the path row's lead and count.
  ask "save-$name" "$(request save "$look/save")"
  shown
  check "$name: the save path row reads '$lead' ~/... '$items' ($(pk_state | jq -c '[.pathLead, .path, .count]'))" state_is --arg l "$lead" --arg n "$items" '.pathLead == $l and .count == $n'
  cancel "save-$name"

  # A 200-character app id: the heading chip elides so the query and its match stay in the card.
  ask "long-$name" "$(request open "$look/shots" false "$long")"
  shown
  wtype down
  until_ok 3000 state_is '.match != ""'
  check "$name: a 200-character app elides the heading and keeps the query and '$match' in the card ($(pk_state | jq -c '{headingTruncated, typed, match, cardSize, boxes}'))" state_is --arg m "$match" ".headingTruncated and (.typed | endswith(\"down\")) and .match == \$m and ($inside)"
  cancel "long-$name"
done

exit $((fails > 0))
}
