#!/usr/bin/env bash
# The picker as its board draws it: the preview's meta lines with the size read from the image's header, the heading chips, the folder and save path rows, the several-files key strip, and a heading that never pushes the query out of the card.
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
preview_of() { pk_state | jq -c '{previewName, preview, previewBadge, previewLines}'; }
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

# The preview: the header's size, not the bounded one Qt decoded, as bare values; no dimensions for a PDF.
ask preview "$(request open "$look/shots")"
shown
cursor_to Photo.jpg
check "a 640 x 480 JPEG draws 640 × 480 px ($(until_ok 3000 state_is '.previewDims != ""'; preview_of))" state_is '.previewDims == "640 × 480 px" and .previewName == "Photo.jpg"'
cursor_to Report.pdf
check "a PDF draws no dimensions line and no picture ($(until_ok 2000 state_is '.previewName == "Report.pdf"'; preview_of))" until_ok 2000 state_is '.previewName == "Report.pdf" and .preview == false and .previewDims == "" and .previewLines[0:1] == ["184 KB"] and (.previewLines | length) == 2'
check "the PDF's badge reads PDF" state_is '.previewBadge == "PDF"'

cursor_to Wide-Shot.png
until_ok 3000 state_is '.preview and .previewDims != ""'
check "a 1600 x 1200 PNG draws 1600 × 1200 px, the name in real case ($(preview_of))" state_is '.preview and .previewDims == "1600 × 1200 px" and .previewLines[0] == "1600 × 1200 px" and .previewName == "Wide-Shot.png"'
check "the date has a comma before the time" state_is '.previewLines[2] | test("^[0-9]{1,2} [A-Z][a-z]{2} [0-9]{4}, [0-9]{2}:[0-9]{2}$")'
check "the badge reads PNG" state_is '.previewBadge == "PNG"'

# Several files: the marked chip and the key strip.
wtype -k Escape
until_ok 3000 answered preview
ask multi "$(request open "$look/shots" true)"
shown
check "a several-files request keys the strip as typed ($(pk_state | jq -c .hint))" state_is '.hint == "↵ open · tab places · ctrl+l path · ctrl+h hidden · ctrl+space select · ctrl+, sort: name · esc"'
check "and no chip while nothing is marked" state_is '.chip == ""'
for n in IMG_2039.HEIC IMG_2040.HEIC IMG_2041.HEIC; do
  cursor_to "$n"
  mark
done
check "three marked files chip the heading 3 marked ($(pk_state | jq -c '[.chip, .marked]'))" until_ok 1000 state_is '.chip == "3 marked"'
# IMG_2039 is marked and off the cursor, Photo.jpg is an unmarked file.
check "a marked row off the cursor draws its name at contrast 4.5 or more ($(row_look IMG_2039.HEIC))" ratio_at_least 4.5 IMG_2039.HEIC
check "a marked file draws ✓ and an unmarked one nothing ($(row_look IMG_2039.HEIC) $(row_look Photo.jpg))" state_is '(.rows[] | select(.name == "IMG_2039.HEIC") | .mark) == "✓" and (.rows[] | select(.name == "Photo.jpg") | .mark) == ""'
cancel multi

# A folder request: its chip, the path row's count and the Items head.
ask folder "$(request folder "$look/pick")"
shown
check "a folder request chips the heading folders only, counts 2 folders, heads Name ↑, Items, Modified ($(pk_state | jq -c '[.chip, .count, .heads]'))" state_is '.chip == "folders only" and .count == "2 folders · files hidden" and .heads == ["Name ↑", "Items", "Modified"]'
cancel folder

# Save: the path row's count.
ask save "$(request save "$look/save")"
shown
check "the save path row counts 3 items ($(pk_state | jq -c '[.path, .count]'))" state_is '.count == "3 items"'
cancel save

# A 200-character app id: the heading chip elides so the query and its match stay in the card.
ask long "$(request open "$look/shots" false "$long")"
shown
wtype down
until_ok 3000 state_is '.match != ""'
check "a 200-character app elides the heading and keeps the query and its match in the card ($(pk_state | jq -c '{headingTruncated, typed, match, cardSize, boxes}'))" state_is ".headingTruncated and (.typed | endswith(\"down\")) and .match == \"→ Downloads\" and ($inside)"
cancel long

exit $((fails > 0))
}
