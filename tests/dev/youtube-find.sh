#!/usr/bin/env bash
# The YouTube App finds playlists and channels as well as videos: h and l move the type filter under the field and search the query again under it, and each type's rows draw as the boards draw them.
{
source "$(dirname "$0")/lib.sh"

yt_qml=$repo/shell/youtube.qml
work=$(mktemp -d)
cleanup() {
  systemctl --user stop 'youtube-video-*' youtube-audio 2>/dev/null
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
times_logged() { grep -cxF -- "$1" "$calls" 2>/dev/null; }
calls_text() { tail -n 4 "$calls" 2>/dev/null | cut -c1-60 | tr '\n' '|'; }
logged_times() { [ "$(times_logged "$1")" = "$2" ]; }
searches() { cat "$calls" 2>/dev/null | grep -c "^search ${1:-}"; }

# The second page of a videos search answers 1 s late, and a playlists search 0.5 s late while $work/slow-playlists is there, as a slow network would, so keys pressed while they load are seen; every other call is the fake's.
slow=$work/slow-youtube
cat >"$slow" <<EOF
#!/usr/bin/env bash
[ "\$*" = "search nujabes videos 20" ] && sleep 1
[ "\$*" = "search nujabes playlists 0" ] && [ -f "$work/slow-playlists" ] && sleep 0.5
exec "$repo/bin/dev-fake-youtube" "\$@"
EOF
chmod +x "$slow"

until_ok 3000 status_theme artboard
# The nested session's XDG_STATE_HOME is scratch already and holds the theme the App draws in, so only data and cache move.
exec_line="env DOTS_DEV_DIR=$DOTS_DEV_DIR DOTS_MACHINE=ytcheck DOTS_YOUTUBE=$slow DOTS_YOUTUBE_MPV=$repo/dev/youtube/mpv $mise_dirs XDG_DATA_HOME=$work XDG_CACHE_HOME=$work $repo/bin/dots-youtube"
niri msg action spawn -- sh -c "exec $exec_line >>'$log' 2>&1"
until_ok 5000 yt_up
check "the filter reads Videos Playlists Channels with Videos on ($(yt_state | jq -c '{type, chips: .look.chips, on: .look.chipsOn}'))" \
  yt_is '.type == "videos" and .look.chips == ["Videos", "Playlists", "Channels"] and .look.chipsOn == [true, false, false]'

wtype l
until_ok 1000 yt_is '.type == "playlists"'
playlists_on() { yt_is '.look.chipsOn == [false, true, false]' && [ "$(searches)" = 0 ]; }
check "l moves the filter to Playlists, with no search for an empty field ($(yt_state | jq -c '{type, on: .look.chipsOn}'))" playlists_on

wtype /
until_ok 1000 yt_is '.focus == "field"'
wtype nujabes
until_ok 1000 yt_is '.query == "nujabes"'
wtype -k Return
until_ok 3000 yt_is '.rows | length == 3'
check "Enter searches playlists ($(calls_text))" logged "search nujabes playlists 0"
check "each playlist row draws its count where a video draws its duration ($(yt_state | jq -c '[.drawn[] | [.title, .duration]]'))" \
  yt_is '[.rows[].kind] == ["playlist", "playlist", "playlist"] and [.drawn[].duration] == ["14 videos", "300 videos", ""] and [.drawn[].title] == ["Modal Soul", "Lofi Archive", "Private Mix"]'
check "the list head counts the 3 rows ($(yt_state | jq -c .look.results))" yt_is '.look.results == ["Results", "3"]'
wtype j
wtype j
sleep 0.3
check "a search of fewer than 20 rows asks for no next page, though the cursor is on its last rows ($(calls_text))" test "$(searches 'nujabes playlists')" = 1

wtype l
until_ok 3000 yt_is '.type == "channels" and ([.rows[].kind] | unique) == ["channel"]'
check "l on the results searches the query again as Channels ($(calls_text))" logged "search nujabes channels 0"
check "each channel row draws its name over its handle, with no duration ($(yt_state | jq -c '[.drawn[] | [.title, .channel, .duration]]'))" \
  yt_is '[.drawn[] | [.title, .channel, .duration]] == [["Nujabes", "@nujabes", ""], ["Quiet Corner", "", ""], ["Hydeout Productions", "@hydeout", ""]] and .look.chipsOn == [false, false, true]'
wtype l
sleep 0.3
stays_channels() { yt_is '.type == "channels"' && [ "$(searches)" = 2 ]; }
check "l on Channels stays there and searches nothing more ($(yt_state | jq -c .type))" stays_channels

wtype s
sleep 0.3
check "s on a channel row saves nothing ($(yt_state | jq -c '.look.sidebar[1]'))" yt_is '.look.sidebar | index("Saved 0") != null'

wtype -k Left
until_ok 1000 yt_is '.type == "playlists"'
wtype h
until_ok 3000 yt_is '.type == "videos" and (.rows | length) == 20'
back_to_videos() { [ "$(times_logged 'search nujabes playlists 0')" = 2 ] && logged "search nujabes videos 0"; }
check "Left then h come back to Videos, searching each type on the way ($(calls_text))" back_to_videos
check "Videos lists 20 video rows ($(yt_state | jq -c '[.rows[].kind] | unique'))" yt_is '([.rows[].kind] | unique) == ["video"] and .look.chipsOn == [true, false, false]'

# Paging: the next 20 come when the cursor reaches the last 5 rows, once while they load.
press_j() { for _ in $(seq "$1"); do wtype j; done; }
press_j 14
until_ok 1000 yt_is '.cursor == 14'
sleep 0.3
check "row 15 of 20 asks for nothing yet ($(calls_text))" test "$(searches 'nujabes videos 20')" = 0
first_ids=$(yt_state | jq -c '[.rows[].id]')
wtype j
until_ok 1000 yt_is '.paging.loading'
press_j 4
until_ok 3000 yt_is '.rows | length > 20'
check "row 16 asked for offset 20 once, though j went on while it loaded ($(calls_text))" test "$(times_logged 'search nujabes videos 20')" = 1
check "the list then holds 39 rows, page 2's repeat of fakeVid0007 dropped ($(yt_state | jq -c '{n: (.rows | length), sevens: ([.rows[] | select(.id == "fakeVid0007")] | length)}'))" \
  yt_is '(.rows | length) == 39 and ([.rows[] | select(.id == "fakeVid0007")] | length) == 1 and ([.rows[].id] | unique | length) == 39'
check "the first 20 rows keep their order ($(yt_state | jq -c '[.rows[0:3][].id]'))" yt_is --argjson f "$first_ids" '[.rows[0:20][].id] == $f'
check "the cursor stays on row 20 and in view ($(yt_state | jq -c '{cursor, listed}'))" \
  yt_is '.cursor == 19 and .listed.current == 19 and .listed.top <= 19 and .listed.bottom >= 19'
press_j 15
until_ok 3000 yt_is '.rows | length == 44'
check "row 35 of 39 asked for offset 40, whose 5 rows end the list ($(calls_text))" \
  yt_is '(.rows | length) == 44 and .paging.more == false and .rows[43].id == "fakeVid0045"'
press_j 10
until_ok 1000 yt_is '.cursor == 43'
sleep 0.3
check "the last row asks for no page past the end ($(calls_text))" test "$(searches 'nujabes videos')" = 3

# A page asked for while a new search runs belongs to the old list, so it never lands under the new one's rows.
wtype l
until_ok 3000 yt_is '.type == "playlists" and (.rows | length) == 3'
wtype h
until_ok 3000 yt_is '.type == "videos" and (.rows | length) == 20'
press_j 14
until_ok 1000 yt_is '.cursor == 14'
touch "$work/slow-playlists"
wtype l
wtype j
until_ok 1000 logged_times 'search nujabes videos 20' 2
sleep 2
check "a page asked for during the playlists search does not land under its rows ($(yt_state | jq -c '{n: (.rows | length), kinds: ([.rows[].kind] | unique)}'))" \
  yt_is '(.rows | length) == 3 and ([.rows[].kind] | unique) == ["playlist"]'
rm "$work/slow-playlists"
wtype h
until_ok 3000 yt_is '.type == "videos" and (.rows | length) == 20'

# A channel row opens its uploads, newest first, with the keys a search row has.
wtype l
until_ok 3000 yt_is '.type == "playlists" and (.rows | length) == 3'
wtype l
until_ok 3000 yt_is '.type == "channels" and (.rows | length) == 3'
wtype -k Return
until_ok 3000 yt_is '.opened.kind == "channel" and (.rows | length) == 20'
check "Enter on the channel Nujabes asks for its uploads ($(calls_text))" logged "channel UCfakeChan00000000000001 0"
check "its uploads list under its name, the newest first ($(yt_state | jq -c '{head: .look.results, first: [.rows[0:3][].id], cursor}'))" \
  yt_is '.look.results == ["Nujabes", "20"] and [.rows[0:3][].id] == ["fakeUpl0001", "fakeUpl0002", "fakeUpl0003"] and .cursor == 0'
press_j 15
until_ok 3000 yt_is '.rows | length == 25'
check "row 16 of the uploads asks for their next page ($(calls_text))" logged "channel UCfakeChan00000000000001 20"
wtype -k Return
until_ok 3000 yt_is '.units | length == 1'
check "Enter on an upload plays it in a window ($(yt_state | jq -c .units))" yt_is '.units | length == 1'
# The video's window takes the keys once it maps, so it goes before the next key.
mpv_count() { [ "$(niri msg -j windows | jq '[.[] | select(.app_id == "mpv")] | length')" = "$1" ]; }
yt_focused() { niri msg -j focused-window | jq -e '.app_id == "youtube"' >/dev/null; }
until_ok 5000 mpv_count 1
systemctl --user stop "$(yt_state | jq -r '.units[0]').service"
until_ok 3000 mpv_count 0
until_ok 3000 yt_focused
wtype j
wtype m
wtype j
wtype a
wtype s
keys_acted() { yt_is '.look.sidebar[1:3] == ["Saved 1", "History 3"]'; }
until_ok 3000 keys_acted
check "m, a and s act on uploads as on search rows ($(yt_state | jq -c '.look.sidebar[1:3]'))" keys_acted
wtype -k Escape
until_ok 1000 yt_is '.opened == null'
check "Esc returns to the channel results on the channel's row ($(yt_state | jq -c '{n: (.rows | length), cursor, head: .look.results}'))" \
  yt_is '(.rows | length) == 3 and .rows[0].kind == "channel" and .cursor == 0 and .look.results == ["Results", "3"]'
wtype j
wtype -k Return
until_ok 3000 yt_is '.opened.id == "UCfakeChan00000000000002" and .paging.loading == false'
check "a channel with no uploads reads No videos on this channel ($(yt_state | jq -c '{empty, head: .look.results}'))" \
  yt_is '.empty == ["No videos on this channel"] and .look.results == ["Quiet Corner", "0"]'
wtype -k Escape
until_ok 1000 yt_is '.opened == null'
check "Esc comes back to row 2 ($(yt_state | jq -c .cursor))" yt_is '.cursor == 1'

# A playlist row lists every item at once.
wtype h
until_ok 3000 yt_is '.type == "playlists" and (.rows | length) == 3 and .opened == null'
wtype -k Return
until_ok 3000 yt_is '.opened.kind == "playlist" and (.rows | length) == 14'
check "Enter on a playlist row lists its items with their durations under its title and count ($(yt_state | jq -c '{head: .look.results, d: [.drawn[0:3][].duration]}'))" \
  yt_is '.look.results == ["Modal Soul", "14 videos"] and ([.rows[] | select(.duration == "")] | length) == 0 and .drawn[0].duration == "4:27"'
press_j 13
sleep 0.3
check "the playlist's last rows ask for no more ($(calls_text))" test "$(cat "$calls" | grep -c '^playlist ')" = 1
wtype -k Escape
until_ok 1000 yt_is '.opened == null'
wtype j
wtype j
wtype -k Return
until_ok 3000 yt_is '.error != null'
check "a playlist that does not exist shows YouTube's own line in the list ($(yt_state | jq -c '.failed | {fix, raw}'))" \
  yt_is '.error.error == "The playlist does not exist." and .failed.fix == "The playlist does not exist." and (.failed.raw | test("YouTube said"))'
wtype -k Return
until_ok 3000 logged_times 'playlist PLfakePrivate1' 2
check "Enter on the failure asks for the playlist again ($(calls_text))" test "$(times_logged 'playlist PLfakePrivate1')" = 2
wtype -k Escape
until_ok 1000 yt_is '.opened == null and .error == null'
check "Esc returns to the playlist results on row 3 ($(yt_state | jq -c '{cursor, n: (.rows | length)}'))" yt_is '.cursor == 2 and (.rows | length) == 3'

# A pasted YouTube link opens its item instead of searching; another site's is searched as text.
paste_enter() {
  wtype /
  until_ok 1000 yt_is '.focus == "field"'
  wtype -M ctrl a -m ctrl
  wtype -- "$1"
  until_ok 1000 yt_is --arg q "$1" '.query == $q'
  wtype -k Return
}
watch='https://www.youtube.com/watch?v=fakeVid0003&list=PLfakeList0001&t=30'
paste_enter "$watch"
until_ok 3000 yt_is '(.rows | length) == 1 and .rows[0].id == "fakeVid0003"'
check "a watch URL with list= and t= resolves to its video, the only row, not the playlist ($(calls_text))" \
  yt_is '(.rows | length) == 1 and .rows[0].id == "fakeVid0003" and .opened == null and .look.results == ["Results", "1"]'
check "and asks for no search and no playlist ($(calls_text))" \
  bash -c "tail -n 2 '$calls' | grep -qxF 'resolve $watch' && [ \"\$(grep -c '^playlist PLfakeList0001' '$calls')\" = 1 ]"
wtype -k Return
until_ok 3000 yt_is '.units | length == 2'
check "Enter on it plays it ($(yt_state | jq -c .units))" yt_is '.units | length == 2'
until_ok 5000 mpv_count 1
systemctl --user stop "$(yt_state | jq -r '.units[1]').service"
until_ok 3000 mpv_count 0
until_ok 3000 yt_focused
paste_enter https://youtu.be/fakeVid0004
until_ok 3000 yt_is '.rows[0].id == "fakeVid0004"'
check "a youtu.be link opens its video ($(yt_state | jq -c '[.rows[].id]'))" yt_is '[.rows[].id] == ["fakeVid0004"]'
paste_enter 'https://music.youtube.com/watch?v=fakeVid0005'
until_ok 3000 yt_is '.rows[0].id == "fakeVid0005"'
check "a music.youtube.com link opens its video ($(yt_state | jq -c '[.rows[].id]'))" yt_is '[.rows[].id] == ["fakeVid0005"]'
paste_enter 'https://www.youtube.com/playlist?list=PLfakeList0002'
until_ok 3000 yt_is '.opened.kind == "playlist" and (.rows | length) == 300'
check "a playlist link lists its items under its title and count ($(yt_state | jq -c '{head: .look.results, n: (.rows | length)}'))" \
  yt_is '.look.results == ["Lofi Archive", "300 videos"] and (.rows | length) == 300'
paste_enter https://www.youtube.com/@nujabes
until_ok 3000 yt_is '.opened.kind == "channel" and (.rows | length) == 20'
check "an @handle link lists that channel's uploads ($(calls_text))" \
  yt_is '.look.results == ["Nujabes", "20"] and .rows[0].id == "fakeUpl0001"'
check "asking for the handle's uploads ($(calls_text))" logged "channel @nujabes 0"
paste_enter https://www.youtube.com/channel/UCfakeChan00000000000003
until_ok 3000 yt_is '.opened.id == "UCfakeChan00000000000003" and (.rows | length) == 3'
check "a /channel/ link lists that channel's uploads ($(yt_state | jq -c '{head: .look.results}'))" yt_is '.look.results == ["Hydeout Productions", "3"]'
paste_enter https://vimeo.com/123
until_ok 3000 logged "search https://vimeo.com/123 playlists 0"
check "another site's URL is searched as text, with no resolve ($(calls_text))" \
  bash -c "! grep -q '^resolve https://vimeo' '$calls'"
until_ok 3000 yt_is '.opened == null'
check "its results replace the opened channel ($(yt_state | jq -c '{opened, head: .look.results}'))" yt_is '.opened == null and .look.results[0] == "Results"'

wtype -k Escape
until_ok 3000 yt_gone
check "Esc closes the App" yt_gone

errs=$(grep -E 'TypeError|ReferenceError|SyntaxError|Failed to load|is not a type|Cannot assign|Unable to assign|Cannot read propert|unavailable' "$log")
check "YouTube's log has no QML errors${errs:+: $(head -c 300 <<<"$errs")}" test -z "$errs"

exit $((fails > 0))
}
