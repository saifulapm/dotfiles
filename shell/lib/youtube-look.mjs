// How the YouTube App reads under a token set, as its board draws it: the title strip, the sidebar, the field and chips, the legend, the empty views and the error block.
import { listLook, plainTones } from './voice.mjs';
import { EMPTY, count } from './youtube.mjs';

const SEARCH_KEYS = [['j/k', 'move'], ['↵', 'play video'], ['m', 'play audio'], ['a', 'add to queue'], ['s', 'save'], ['p', 'add to playlist'], ['d/D', 'download audio/video'], ['/', 'search'], ['tab', 'sidebar'], ['esc', 'back']];
// A Playlist's keys play it whole; x and Shift+J/K act on the item under the cursor.
const PLAYLIST_KEYS = [['↵', 'play as video'], ['m', 'play in queue'], ['S', 'shuffle'], ['a', 'add to queue'], ['x', 'remove'], ['⇧J/⇧K', 'move'], ['d/D', 'download missing'], ['r', 'repeat'], ['esc', 'back']];
// An opened playlist's s saves the whole of it as a Playlist.
const OPENED_KEYS = [['j/k', 'move'], ['s', 'save as a playlist'], ['↵', 'play video'], ['m', 'play audio'], ['a', 'add to queue'], ['/', 'search'], ['tab', 'sidebar'], ['esc', 'back']];
// With the sidebar focused the keys make, rename, delete and open a Playlist.
const SIDEBAR_KEYS = [['n', 'new'], ['e', 'rename'], ['x', 'delete'], ['↵', 'open'], ['tab', 'list']];
const EMPTY_KEYS = [['/', 'search'], ['tab', 'sidebar'], ['esc', 'back']];
const FAILED_KEYS = [['↵', 'try again']].concat(EMPTY_KEYS);

const PLACES = [
  { view: 'search', name: 'Search' },
  { view: 'saved', name: 'Saved' },
  { view: 'history', name: 'History' },
];

export function youtubeLook(tokens) {
  const l = listLook(tokens);
  // The board's tint, field, tiles, thumbnail and error block, which no token carries.
  const tones = plainTones(tokens);
  const tint = { tint: tones.tint, deep: tones.deep, tile: tones.tile, field: tones.field, thumb: tones.thumb, errFill: tones.warnChip, errInk: tones.warn, errText: tones.strong };
  const fonts = (tokens && tokens.type) || { ui: '' };
  return Object.assign(l, {
    title: {
      label: 'YouTube',
      from: 'from the launcher',
      view: (v) => (PLACES.find((p) => p.view === v) || PLACES[0]).name,
    },
    viewFont: fonts.ui,
    viewSize: 14,
    places: PLACES,
    playlists: 'PLAYLISTS',
    noPlaylists: EMPTY.playlists,
    placeholder: 'Search YouTube',
    namePlaceholder: 'Playlist name',
    unavailable: (why) => `Video unavailable · ${why}`,
    toast: { saved: (n) => `Saved as a playlist · ${count(n)}` },
    // A snapshot's new Playlist, marked in the sidebar.
    fresh: 'new',
    // p's picker, headed with its key.
    pick: {
      title: (t) => `Add "${t}" to`,
      chip: 'p',
      already: 'already in',
      newKey: 'n',
      newWord: 'new playlist',
      keys: l.keys([['j/k', 'move'], ['↵', 'add'], ['n', 'new'], ['esc', 'cancel']]),
    },
    hint: '/',
    chips: ['Videos', 'Playlists', 'Channels'],
    results: 'Results',
    // The now-playing line's right side, as the Queue's loop-playlist reads.
    repeat: (on) => (on ? 'repeat on' : 'repeat off'),
    // A failed search's list is its error block, so only try again and the moves away act on it.
    legend(view, failed, focus, opened) {
      if (focus === 'sidebar') return l.keys(SIDEBAR_KEYS);
      if (view === 'search' && !failed && opened === 'playlist') return l.keys(OPENED_KEYS);
      if (view === 'playlist') return l.keys(PLAYLIST_KEYS);
      return l.keys(view !== 'search' ? EMPTY_KEYS : failed ? FAILED_KEYS : SEARCH_KEYS);
    },
    empty(view) {
      if (view === 'saved') return { head: EMPTY.saved.head, key: EMPTY.saved.key, rest: EMPTY.saved.rest };
      if (view === 'history') return { head: '', key: '↵', rest: 'or m plays a video' };
      if (view === 'playlist') return { head: '', key: EMPTY.playlist.key, rest: EMPTY.playlist.rest };
      if (view === 'channel') return { head: 'No videos on this channel', key: '', rest: '' };
      return null;
    },
    failed: {
      head: "YouTube didn't give results",
      key: '↵',
      word: 'try again',
    },
    // x on a Playlist asks under its row.
    confirm: {
      // A name past 40 characters is cut, so the question still ends with what it deletes.
      question: (name, n) => `Delete ${name.length > 40 ? name.slice(0, 39) + '…' : name} and its ${count(n)}?`,
      keys: [{ key: 'y', word: 'delete' }, { key: 'esc', word: 'keep' }],
    },
    // The download mark in the slot before a row's duration, on a grey tile.
    mark: { size: 12, stroke: tint.deep, width: 2, tile: { width: 22, height: 20, radius: 6, color: tint.tile } },
    // A row whose download failed says why in its channel line, and Enter tries again (ruling DS2ESKWX).
    retry: (reason) => `download failed · ${reason} · ↵ retry`,
    retryColor: tint.errInk,
    fieldRadius: 14,
    rowRadius: 10,
    tint,
  });
}
