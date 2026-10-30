# Sourced by the passage midnight checks in place of lib.sh: a deen that logs each call, and a shell in a zone whose midnight comes at least $1 s after this runs.
texts=$HOME/.local/share/deen
work=$(mktemp -d)
echo ok >"$work/mode"
# ok passes to the real deen on dots apply's texts; hang never answers.
cat >"$work/deen" <<FAKE
#!/bin/sh
echo "\$*" >>$work/calls
[ "\$(cat $work/mode)" != hang ] || exec sleep 600
DEEN_DATA=$texts/quran.json DEEN_WORDS=$texts/words.json DEEN_DUAS=$texts/duas.json DEEN_HADITH=$texts/hadith exec $(command -v deen) "\$@"
FAKE
chmod +x "$work/deen"
export DOTS_DEV_DEEN=$work/deen
# Midnight falls on a whole UTC minute, so the zone is east of UTC by whole minutes; its name means nothing.
midnight=$((($(date +%s) + ${1:?} + 59) / 60 * 60))
east=$(((86400 - midnight % 86400) % 86400))
export DOTS_DEV_TZ=$(printf 'MID-%02d:%02d' $((east / 3600)) $((east / 60 % 60)))
before=$(TZ=$DOTS_DEV_TZ date -d "@$((midnight - 1))" +%F)
after=$(TZ=$DOTS_DEV_TZ date -d "@$midnight" +%F)
source "$(dirname "$0")/lib.sh"
cleanup() { rm -rf "$work"; }

passage() { timeout 0.5 dots-call passage state 2>/dev/null; }
passage_is() { passage | jq -e "$@" >/dev/null 2>&1; }
# The reads deen took for a day's text, not the surahs it is asked for once.
reads() { grep -cv '^api surahs$' "$work/calls"; }
margins_date() { timeout 0.5 dots-call margins state 2>/dev/null | jq -r .right.date; }
# Sleeps until that many seconds after midnight; negative is before it.
until_midnight() { local s=$((midnight + $1 - $(date +%s))); ((s <= 0)) || sleep "$s"; }
