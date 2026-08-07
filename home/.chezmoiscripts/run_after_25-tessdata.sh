#!/usr/bin/env bash
# tessdata — extra OCR languages for bin/screenshot-ocr, in a USER-LOCAL
# directory rather than /usr/share/tesseract/tessdata.
#
# Fedora does package these (tesseract-langpack-ben and friends), but every
# one of them needs root, which means a fresh-machine apply stops to ask for a
# password. tesseract takes --tessdata-dir, so dropping the .traineddata into
# ~/.local/share/tessdata does the same job with no sudo and no rpm — and the
# language set then lives in this repo like everything else.
#
# THE SYMLINK IS NOT OPTIONAL: --tessdata-dir REPLACES the search path, it does
# not extend it. Without eng linked in beside ben, adding Bangla would silently
# break English OCR — which is why screenshot-ocr gates on both files existing
# and falls back to plain `-l eng` when either is missing.
#
# tessdata_best rather than tessdata_fast: Bengali is a conjunct-heavy script
# where the fast models lose accuracy, and a screen region is a small enough
# image that the slower model costs milliseconds. Measured 2026-08-08 on
# rendered samples: eng+ben scored 100% on both English and Bangla text, and
# English OCR went 0.09 s -> 0.13 s. Order matters — ben+eng triples the
# English case to 0.27 s, so screenshot-ocr asks for eng+ben.
set -uo pipefail

dest="$HOME/.local/share/tessdata"
sys="/usr/share/tesseract/tessdata"
langs=(ben)
base="https://github.com/tesseract-ocr/tessdata_best/raw/main"

warn() { echo "tessdata: $*" >&2; }

command -v tesseract >/dev/null 2>&1 || exit 0

mkdir -p "$dest"

# English comes from the rpm; link rather than re-download so the two can never
# drift, and so this costs nothing on a machine that already has it.
if [ -f "$sys/eng.traineddata" ]; then
  ln -sfn "$sys/eng.traineddata" "$dest/eng.traineddata"
else
  warn "no system eng.traineddata — screenshot-ocr will stay on the default path"
fi

for l in "${langs[@]}"; do
  [ -s "$dest/$l.traineddata" ] && continue
  if curl -fsSL -o "$dest/$l.traineddata.part" "$base/$l.traineddata" &&
    mv "$dest/$l.traineddata.part" "$dest/$l.traineddata"; then
    echo "tessdata: fetched $l"
  else
    rm -f "$dest/$l.traineddata.part"
    warn "$l failed to download — OCR falls back to English only"
  fi
done

exit 0
