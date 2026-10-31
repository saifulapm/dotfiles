#!/usr/bin/env bash
# Enter in the YouTube App's field searches through DOTS_YOUTUBE and lists its 20 rows, each title one plain line, each thumbnail decoded at no more than twice its drawn size or, with none on disk, its theme's placeholder; a later search's answer wins over an earlier one still running.
{
source "$(dirname "$0")/lib.sh"

yt_qml=$repo/shell/youtube.qml
work=$(mktemp -d)
cleanup() {
  systemctl --user stop 'youtube-video-*' 2>/dev/null
  rm -rf "$work"
}
log=$work/youtube.log
calls=$DOTS_DEV_DIR/youtube.log

yt_state() { timeout 0.5 qs ipc -p "$yt_qml" call youtube state 2>/dev/null; }
yt_is() { yt_state | jq -e "$@" >/dev/null 2>&1; }
yt_windows() { niri msg -j windows | jq '[.[] | select(.app_id == "youtube")] | length'; }
yt_up() { [ "$(yt_windows)" = 1 ] && yt_is '.firstFrameMs != null'; }
yt_gone() { [ "$(yt_windows)" = 0 ]; }
status_theme() { shell_status | jq -e --arg t "$1" '.theme == $t and .transition == ""' >/dev/null; }
logged() { grep -qxF -- "$1" "$calls" 2>/dev/null; }
calls_text() { cat "$calls" 2>/dev/null | tr '\n' '|'; }

# A search for slow answers 1.5 s late with one row of its own, as a slow network would; every other call is the fake's.
slow=$work/slow-youtube
cat >"$slow" <<EOF
#!/usr/bin/env bash
if [ "\$1" = search ] && [ "\$2" = slow ]; then
  echo "\$*" >>"$calls"
  sleep 1.5
  echo '{"rows":[{"id":"slowVid0001","title":"Slow","channel":"Slow","duration":1,"thumb":"slowVid0001"}],"next":1}'
  exit 0
fi
exec "$repo/bin/dev-fake-youtube" "\$@"
EOF
chmod +x "$slow"

"$repo/bin/dots" theme paper >/dev/null
until_ok 3000 status_theme paper
# The nested session's XDG_STATE_HOME is scratch already and holds the theme the App draws in, so only data and cache move.
exec_line="env DOTS_DEV_DIR=$DOTS_DEV_DIR DOTS_YOUTUBE=$slow DOTS_YOUTUBE_MPV=$repo/dev/youtube/mpv $mise_dirs XDG_DATA_HOME=$work XDG_CACHE_HOME=$work $repo/bin/dots-youtube"
niri msg action spawn -- sh -c "exec $exec_line >>'$log' 2>&1"
until_ok 5000 yt_up
check "the App opens on Search ($(yt_state | jq -c '{view, focus}'))" yt_is '.view == "search" and .focus == "list"'

wtype /
until_ok 1000 yt_is '.focus == "field"'
wtype nujabes
until_ok 1000 yt_is '.query == "nujabes"'
wtype -k Return
until_ok 3000 yt_is '.rows | length == 20'
check "Enter asked the CLI for search nujabes videos 0 ($(calls_text))" logged "search nujabes videos 0"
check "focus moved to the list on row 0 ($(yt_state | jq -c '{focus, cursor}'))" yt_is '.focus == "list" and .cursor == 0'
check "20 rows are drawn under RESULTS 20 ($(yt_state | jq -c '{n: (.drawn | length), results: .look.results}'))" \
  yt_is '(.drawn | length) == 20 and .look.results == ["RESULTS", "20"] and ([.drawn[].id] == [.rows[].id])'
check "row 3 draws as one line with no newline, U+202E or ESC ($(yt_state | jq -c '.drawn[3] | {title, titleLines, channel}'))" \
  yt_is '.drawn[3] | .title == "Low Tide Radio" and .titleLines == 1 and .channel == "lofi archive" and (.title | test("[\n‮\u001b]") | not)'
check "row 5's 300-character title and channel each draw on one elided line ($(yt_state | jq -c '.drawn[5] | {titleLines, titleElided, channelElided}'))" \
  yt_is '.drawn[5] | (.title | length) == 300 and .titleLines == 1 and .titleElided and .channelElided'

thumbs_shown() { yt_is '[.drawn[] | select(.id != "fakeVid0008") | .thumb.shown] | length == 19 and all'; }
until_ok 3000 thumbs_shown
check "within 3 s every row but fakeVid0008 shows its thumbnail ($(yt_state | jq -c '[.drawn[] | select(.thumb.shown)] | length'))" thumbs_shown
check "each thumbnail is its row's file ($(yt_state | jq -c '[.drawn[] | select(.thumb.shown) | .thumb.file][0:2]'))" \
  yt_is 'all(.drawn[] | select(.thumb.shown); .thumb.file == .id + ".jpg")'
check "fakeVid0008 has no file and keeps Paper's hatched placeholder ($(yt_state | jq -c '.drawn[7] | {id, thumb}'))" \
  yt_is '.look.viewFont == "Instrument Serif" and (.drawn[7] | .id == "fakeVid0008" and .thumb.shown == false and .thumb.placeholder == "hatched")'
check "each shown thumbnail decodes at no more than twice its drawn 72x40 ($(yt_state | jq -c '.drawn[0].thumb | {width, height, decodedWidth, decodedHeight}'))" \
  yt_is '[.drawn[] | select(.thumb.shown) | .thumb] | length == 19 and all(.width == 72 and .height == 40 and .decodedWidth > 0 and .decodedHeight > 0 and .decodedWidth <= 2 * .width and .decodedHeight <= 2 * .height)'
page_ids=$(jq -r '[.rows[].thumb] | join(" ")' "$repo/dev/youtube/search.json")
check "the App asked thumbs once, for the page's 20 ids ($(grep -c '^thumbs ' "$calls" 2>/dev/null))" \
  test "$(grep '^thumbs ' "$calls" 2>/dev/null)" = "thumbs $page_ids"
check "with 20 thumbnails drawn the first frame was $(yt_state | jq .firstFrameMs) ms and RSS is $(yt_state | jq .rssKiB) KiB, under 250 MiB" \
  yt_is '.firstFrameMs < 500 and .rssKiB > 0 and .rssKiB < 256000'

# A second Enter while the first search runs: the first's late answer is dropped.
wtype /
until_ok 1000 yt_is '.focus == "field"'
wtype -k End
for _ in 1 2 3 4 5 6 7; do wtype -k BackSpace; done
wtype slow
until_ok 1000 yt_is '.query == "slow"'
wtype -k Return
until_ok 1000 logged "search slow videos 0"
wtype /
until_ok 1000 yt_is '.focus == "field"'
for _ in 1 2 3 4; do wtype -k BackSpace; done
wtype nujabes
until_ok 1000 yt_is '.query == "nujabes"'
wtype -k Return
searched_twice() { [ "$(grep -c '^search nujabes' "$calls" 2>/dev/null)" = 2 ]; }
until_ok 1000 searched_twice
sleep 2.5
check "the second search's 20 rows stand after the first's late answer came ($(yt_state | jq -c '{n: (.rows | length), first: .rows[0].id}'))" \
  yt_is '(.rows | length) == 20 and .rows[0].id == "fakeVid0001" and ([.rows[].id] | index("slowVid0001") == null)'

wtype -k Escape
until_ok 3000 yt_gone
check "Esc closes the App" yt_gone

errs=$(grep -E 'TypeError|ReferenceError|SyntaxError|Failed to load|is not a type|Cannot assign|Unable to assign|Cannot read propert|unavailable' "$log")
check "YouTube's log has no QML errors${errs:+: $(head -c 300 <<<"$errs")}" test -z "$errs"

exit $((fails > 0))
}
