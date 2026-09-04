#!/usr/bin/env bash
# Sweeps up after vicinae's "Quran: Random Verse", replaced by the Islamic
# Hub's Read screen on 2026-09-05.
#
# The script fetched a random ayah from alquran.cloud into a floating foot
# window and hand-drove `fribidi --nopad --nobreak --reordernsm` to get the
# Arabic the right way round, because foot shapes grapheme clusters rather than
# text runs and does no bidi at all. Qt shapes and orders Arabic correctly for
# free, which is why docs/deen-2026-09-04.md §1 said from the start that this
# script survives only until the Mushaf screen replaces it. It does now: the
# Read screen draws any surah, word by word, tajweed coloured, from local data
# and with no network call at all.
#
# WHY THIS IS NOT LEFT TO run_after_50. That sweep is exact and deliberately
# narrow — a symlink that dangles AND points inside the repo. Vicinae's scripts
# are deployed as REGULAR FILES (chezmoi copies them; they carry the
# `executable_` prefix), so the deleted source leaves a real 2 KB script behind
# that no predicate about dangling links will ever match. It would have gone on
# offering "Quran: Random Verse" in the launcher for ever.
#
# run_after_, not run_once_after_, for the reason run_after_39 spells out: a
# run_once_ script is recorded as done the first time it runs, and the other two
# machines have not applied this yet. The guard IS the state — it costs one
# `grep -q` per apply and disarms itself the moment the file is gone.
set -uo pipefail

target="$HOME/.local/share/vicinae/scripts/quran-verse.sh"

# Guarded on OUR marker, not merely on the path. A regular file cannot be
# tested the way run_after_41 tests a stale symlink (`-L` and not `-e`), so the
# equivalent care is to check the file is the one this repo wrote: anything
# else at that path is somebody's deliberate replacement and is left alone.
if [ -f "$target" ] && grep -q '@vicinae.title Quran: Random Verse' "$target" 2>/dev/null; then
  rm -f "$target" \
    && echo "quran-verse-remove: dropped the random-ayah launcher entry (the hub's Read screen replaces it)"
fi

exit 0
