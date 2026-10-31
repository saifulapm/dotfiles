#!/usr/bin/env bash
# s in an opened YouTube playlist, or on a playlist row, saves its items, in their order, as a new Playlist named after it: the head counts reading <n> of <count> while dots-youtube-api snapshot reads, a toast counts what was saved, and the sidebar marks the new Playlist until it is opened; the original gaining an item later leaves the snapshot as it was, and 5000 items read with the App still answering.
{
source "$(dirname "$0")/lib.sh"

yt_qml=$repo/shell/youtube.qml
work=$(mktemp -d)
cleanup() {
  systemctl --user stop 'youtube-video-*' 2>/dev/null
  rm -f "$DOTS_DEV_DIR/youtube-grow"
  rm -rf "$work"
}
log=$work/youtube.log
store=$work/data/dots/youtube/ytcheck.json

yt_state() { timeout 0.5 qs ipc -p "$yt_qml" call youtube state 2>/dev/null; }
yt_is() { yt_state | jq -e "$@" >/dev/null 2>&1; }
yt_windows() { niri msg -j windows | jq '[.[] | select(.app_id == "youtube")] | length'; }
yt_up() { [ "$(yt_windows)" = 1 ] && yt_is '.firstFrameMs != null'; }
yt_gone() { [ "$(yt_windows)" = 0 ]; }
status_theme() { shell_status | jq -e --arg t "$1" '.theme == $t and .transition == ""' >/dev/null; }
sidebar_has() { yt_is --arg s "$1" '.look.sidebar | index($s) != null'; }
# The head's count while the snapshot reads, caught between its first and last page.
reading_midway() { yt_is '.look.results[1] | test("^reading [12]00 of 300$")'; }

"$repo/bin/dots" theme paper >/dev/null
until_ok 3000 status_theme paper

exec_line="env DOTS_DEV_DIR=$DOTS_DEV_DIR DOTS_MACHINE=ytcheck DOTS_YOUTUBE=$repo/bin/dev-fake-youtube DOTS_YOUTUBE_MPV=$repo/dev/youtube/mpv $mise_dirs XDG_DATA_HOME=$work/data XDG_CACHE_HOME=$work $repo/bin/dots-youtube"
open_app() {
  niri msg action spawn -- sh -c "exec $exec_line >>'$log' 2>&1"
  until_ok 5000 yt_up
}
paste_list() {
  wtype /
  until_ok 1000 yt_is '.focus == "field"'
  wtype -M ctrl a -m ctrl
  wtype "https://www.youtube.com/playlist?list=$1"
  wtype -k Return
  until_ok 3000 yt_is --arg id "$1" '.opened.id == $id and .paging.loading == false and (.rows | length) > 0'
}

open_app
paste_list PLfakeList0002
check "the pasted playlist opens its 300 items, s naming save as a playlist ($(yt_state | jq -c '[.opened.title, (.rows | length), .look.legend[1]]'))" \
  yt_is '.opened.title == "Lofi Archive" and (.rows | length) == 300 and .look.legend[1] == "S SAVE AS A PLAYLIST"'
wtype s
until_ok 3000 reading_midway
check "while it reads, the head reads reading <n> of 300 ($(yt_state | jq -c '.look.results'))" reading_midway
until_ok 4000 sidebar_has "Lofi Archive NEW 300"
check "then a Playlist named after it sits in the sidebar with 300, marked new ($(yt_state | jq -c '.look.sidebar'))" sidebar_has "Lofi Archive NEW 300"
check "and the toast reads Saved as a playlist · 300 videos ($(yt_state | jq -c .toast))" yt_is '.toast == "Saved as a playlist · 300 videos"'
check "and the head reads the playlist's own count again ($(yt_state | jq -c '.look.results'))" yt_is '.look.results == ["Lofi Archive", "300 videos"]'
same_order() {
  diff <(jq -r '.PLfakeList0002.rows[].id' "$repo/dev/youtube/playlist-items.json") \
    <(jq -r '.playlists | to_entries[] | select(.value.name == "Lofi Archive") | .value.items | to_entries | sort_by(.value.pos)[] | .key' "$store") >/dev/null
}
until_ok 2000 same_order
check "the store holds its 300 items in the original order" same_order
gone_toast() { yt_is '.toast == ""'; }
until_ok 4000 gone_toast
check "the toast goes after 3 s" gone_toast

# The original gains an item: opened again it lists 301, and the snapshot stays at 300.
touch "$DOTS_DEV_DIR/youtube-grow"
paste_list PLfakeList0002
check "opened again the original lists 301 ($(yt_state | jq -c '.rows | length'))" yt_is '(.rows | length) == 301'
check "and the snapshot still reads 300 ($(yt_state | jq -c '.look.sidebar'))" sidebar_has "Lofi Archive NEW 300"
rm -f "$DOTS_DEV_DIR/youtube-grow"

# Opening the new Playlist takes its mark away.
wtype -k Escape
wtype -k Tab
until_ok 1000 yt_is '.focus == "sidebar"'
wtype j j j
until_ok 1000 yt_is '.view == "playlist"'
check "opening it lists its 300 numbered and drops the mark ($(yt_state | jq -c '[.look.results, .look.sidebar[4]]'))" \
  yt_is '.look.results[0] == "Lofi Archive" and (.look.results[1] | startswith("300 videos")) and .look.sidebar[4] == "Lofi Archive 300" and .drawn[0].number == "1"'
wtype k k k
until_ok 1000 yt_is '.view == "search"'
wtype -k Tab
until_ok 1000 yt_is '.focus == "list"'

# s on a playlist row in the results saves it without opening it.
wtype /
until_ok 1000 yt_is '.focus == "field"'
wtype -M ctrl a -m ctrl
wtype nujabes
wtype -k Escape
until_ok 1000 yt_is '.focus == "list"'
wtype l
until_ok 3000 yt_is '.type == "playlists" and .rows[0].title == "Modal Soul"'
wtype s
until_ok 3000 sidebar_has "Modal Soul NEW 14"
check "s on the Modal Soul row saves its 14 as a Playlist, the results still listed ($(yt_state | jq -c '[.look.sidebar, .opened]'))" \
  yt_is '(.look.sidebar | index("Modal Soul NEW 14")) != null and .opened == null and .type == "playlists"'

# 5000 items: the App answers while they read, and every one is saved.
paste_list PLfakeList5000
wtype s
until_ok 2000 yt_is '.snapshot != null'
# Sampled until the snapshot has landed, so the call that meets its last line and the store's write is among them.
took=()
for _ in $(seq 60); do
  t0=$(now_ms)
  out=$(timeout 3 qs ipc -p "$yt_qml" call youtube state 2>/dev/null)
  took+=($(($(now_ms) - t0)))
  jq -e '.snapshot == null' <<<"$out" >/dev/null 2>&1 && break
  sleep 0.1
done
echo "state call ms during the 5000 read: ${took[*]}"
slowest=$(printf '%s\n' "${took[@]}" | sort -n | tail -1)
check "while 5000 items read, the App answers every state call in under 1 s (slowest $slowest ms)" test "$slowest" -lt 1000
big_saved() { yt_is '.look.sidebar[-1] == "Five thousand NEW 5000" and .toast == "Saved as a playlist · 5,000 videos"'; }
until_ok 15000 big_saved
# A state holding 5000 rows runs to 660 KB, and one qs ipc answer in three that size reads short, so even this check polls.
check "and the snapshot reaches 5000" until_ok 2000 big_saved

# A snapshot keeps an unavailable item with its mark, so it draws without the network.
paste_list PLfakeList0003
wtype s
until_ok 4000 sidebar_has "Mixed tape NEW 4"
kept_mark() { jq -e '.playlists | to_entries[] | select(.value.name == "Mixed tape") | .value.items.fakeGone001.unavailable == "made private"' "$store" >/dev/null 2>&1; }
until_ok 2000 kept_mark
check "a snapshot of Mixed tape keeps its private item marked made private" kept_mark

wtype -k Escape
wtype -k Escape
until_ok 3000 yt_gone

errs=$(grep -E 'TypeError|ReferenceError|SyntaxError|Failed to load|is not a type|Cannot assign|Unable to assign|Cannot read propert|unavailable' "$log")
check "YouTube's log has no QML errors${errs:+: $(head -c 300 <<<"$errs")}" test -z "$errs"

exit $((fails > 0))
}
