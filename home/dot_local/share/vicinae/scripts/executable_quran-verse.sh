#!/usr/bin/env bash
# @vicinae.schemaVersion 1
# @vicinae.title Quran: Random Verse
# @vicinae.mode silent
# @vicinae.icon 📖
# @vicinae.packageName Prayer
# @vicinae.keywords ["quran", "ayah", "verse", "কুরআন"]
# A random ayah — Arabic, Bangla (Muhiuddin Khan) and Sahih International —
# in a floating terminal. Companion to the prayer-times bar widget.
set -euo pipefail
export PATH="$HOME/.dotfiles/bin:$HOME/.local/bin:$PATH"

exec foot-run --app-id=qshell-float -e bash -c '
    n=$((RANDOM % 6236 + 1))
    body="$(curl -fsSL --max-time 15 "https://api.alquran.cloud/v1/ayah/$n/editions/quran-uthmani,bn.bengali,en.sahih")" || {
        echo "Could not reach alquran.cloud"; read -r; exit 1; }
    surah="$(jq -r ".data[0].surah.englishName" <<<"$body")"
    sn="$(jq -r ".data[0].surah.number" <<<"$body")"
    ayah="$(jq -r ".data[0].numberInSurah" <<<"$body")"
    arabic="$(jq -r ".data[0].text" <<<"$body")"
    bangla="$(jq -r ".data[1].text" <<<"$body")"
    english="$(jq -r ".data[2].text" <<<"$body")"
    printf "\n  \033[1mSurah %s (%s:%s)\033[0m\n\n" "$surah" "$sn" "$ayah"
    printf "%s\n\n" "$arabic" | fold -s -w 76 | sed "s/^/  /"
    printf "%s\n\n" "$bangla" | fold -s -w 76 | sed "s/^/  /"
    printf "\033[2m%s\033[0m\n\n" "$english" | fold -s -w 76 | sed "s/^/  /"
    printf "  \033[2mpress enter to close\033[0m"
    read -r
'
