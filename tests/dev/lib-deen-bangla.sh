# Sourced before lib.sh by a check that needs deen's Bangla: the real deen at its checkout, on the texts and hadith corpus its pin's apply builds from the deen-data checkout, written as $work/deen-bangla, since the deen on PATH may predate deen-data; the caller makes $work.
backend=/home/saiful/Codes/deen
sources=/home/saiful/Codes/deen-data
if ! cargo build --offline -q --manifest-path "$backend/Cargo.toml" --bin deen; then
  echo "FAIL the backend at $backend builds"
  exit 1
fi
if ! DEEN_BIN=$backend/target/debug/deen "$backend/scripts/build-data" "$sources" "$work/texts" >/dev/null; then
  echo "FAIL the backend builds its texts from $sources"
  exit 1
fi
printf '#!/bin/sh\nDEEN_DATA=%q DEEN_WORDS=%q DEEN_DUAS=%q DEEN_HADITH=%q DEEN_SOURCES=%q exec %q "$@"\n' \
  "$work/texts/quran.json" "$work/texts/words.json" "$work/texts/duas.json" "$work/hadith" "$sources" "$backend/target/debug/deen" >"$work/deen-bangla"
chmod +x "$work/deen-bangla"
mkdir -p "$work/hadith"
if ! "$work/deen-bangla" hadith fetch >/dev/null; then
  echo "FAIL the backend joins the hadith corpus from $sources"
  exit 1
fi
