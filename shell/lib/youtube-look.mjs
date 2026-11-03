// How the YouTube App reads under a token set, as the three themes' YouTube boards draw it: the title strip, the sidebar, the field and chips, the legend, the empty views and the error block.
import { listLook, mark, plainTones } from './voice.mjs';
import { EMPTY, count } from './youtube.mjs';

// The boards' tints that no token carries: Paper's chosen place, row rule and light ink on a lit row, and Blueprint's warning amber. The plain voice's tint, field, tiles, thumbnail and error block come from the theme's plain tones; one set for all voices, as a theme switch can draw a voice's branch before its look lands.
const TINT = { chosen: '#EFE6D2', rule: '#D8CDB6', onInk: '#D9CFBB', warn: '#FFB547' };

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
  const tones = plainTones(tokens);
  const tint = Object.assign({}, TINT, { tint: tones.tint, deep: tones.deep, tile: tones.tile, field: tones.field, thumb: tones.thumb, errFill: tones.warnChip, errInk: tones.warn, errText: tones.strong });
  const voice = l.voice;
  const plain = voice === 'plain';
  const bracket = voice === 'bracket';
  const m = (s) => mark(l.engraved, s);
  // Blueprint marks each shifted key and spaces the slash in its download pair.
  const SHIFTED = { [m('S')]: m('⇧S'), [m('D/D')]: m('D/⇧D') };
  const DOWNLOAD = { key: m('D/⇧D'), word: 'DOWNLOAD AUDIO / VIDEO' };
  const fonts = (tokens && tokens.type) || { display: '', ui: '' };
  return Object.assign(l, {
    title: {
      label: plain ? 'YouTube' : 'YOUTUBE',
      from: bracket ? 'FROM THE LAUNCHER' : 'from the launcher',
      view: (v) => (PLACES.find((p) => p.view === v) || PLACES[0]).name,
    },
    viewFont: voice === 'caps' ? fonts.display : fonts.ui,
    viewSize: voice === 'caps' ? 18 : plain ? 14 : 12,
    places: PLACES,
    library: bracket ? 'LIBRARY' : '',
    playlists: 'PLAYLISTS',
    noPlaylists: EMPTY.playlists,
    placeholder: 'Search YouTube',
    namePlaceholder: 'Playlist name',
    unavailable: (why) => `Video unavailable · ${why}`,
    toast: { saved: (n) => `Saved as a playlist · ${count(n)}` },
    // A snapshot's new Playlist, marked in the sidebar: Paper sets it in caps as its board's CSS does.
    fresh: plain ? 'new' : 'NEW',
    // p's picker: Paper and Artboard head it with the key, Blueprint with PLAYLISTS; Paper's badge is set in caps as its board's CSS sets it.
    pick: {
      title: (t) => `Add "${t}" to`,
      chip: bracket ? 'PLAYLISTS' : voice === 'caps' ? 'P' : 'p',
      already: bracket ? 'ALREADY IN ✓' : voice === 'caps' ? 'ALREADY IN' : 'already in',
      newKey: bracket ? m('N') : 'n',
      newWord: 'new playlist',
      keys: l.keys([['j/k', 'move'], ['↵', 'add'], ['n', 'new'], ['esc', 'cancel']]),
    },
    hint: bracket ? m('/') : '/',
    typeLabel: plain ? '' : 'TYPE',
    chips: ['Videos', 'Playlists', 'Channels'].map((w) => (bracket ? w.toUpperCase() : w)),
    results: plain ? 'Results' : 'RESULTS',
    // The now-playing line's right side, as the Queue's loop-playlist reads.
    repeat: (on) => (bracket ? (on ? 'REPEAT ON' : 'REPEAT OFF') : on ? 'repeat on' : 'repeat off'),
    // A failed search's list is its error block, so only try again and the moves away act on it.
    legend(view, failed, focus, opened) {
      if (focus === 'sidebar') return l.keys(SIDEBAR_KEYS);
      if (view === 'search' && !failed && opened === 'playlist') return l.keys(OPENED_KEYS);
      if (view === 'playlist') {
        const keys = l.keys(PLAYLIST_KEYS);
        return bracket ? keys.map((k) => Object.assign({}, k, { key: SHIFTED[k.key] || k.key })) : keys;
      }
      const keys = l.keys(view !== 'search' ? EMPTY_KEYS : failed ? FAILED_KEYS : SEARCH_KEYS);
      return bracket ? keys.map((k) => (k.word === 'DOWNLOAD AUDIO/VIDEO' ? DOWNLOAD : k)) : keys;
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
      key: bracket ? m('↵') : '↵',
      word: 'try again',
      // Paper's board heads a stale yt-dlp's block YOUTUBE CHANGED; the other kinds' boards draw no such line.
      kicker: (f) => (voice === 'caps' && f.kind === 'extraction' && f.error.startsWith('yt-dlp ') ? 'YOUTUBE CHANGED' : ''),
    },
    // x on a Playlist asks under its row; Paper's and Artboard's keys keep their case, as their boards draw them.
    confirm: {
      // A name past 40 characters is cut, so the question still ends with what it deletes.
      question: (name, n) => `Delete ${name.length > 40 ? name.slice(0, 39) + '…' : name} and its ${count(n)}?`,
      keys: bracket ? l.keys([['y', 'delete'], ['esc', 'keep']]) : [{ key: 'y', word: 'delete' }, { key: 'esc', word: 'keep' }],
    },
    // The download mark beside a row's duration: Paper's sits in its 16 px end, the others in the slot before the duration.
    mark: plain
      ? { at: 'before', size: 12, stroke: tint.deep, width: 2, tile: { width: 22, height: 20, radius: 6, color: tint.tile } }
      : { at: bracket ? 'before' : 'end', size: 14, stroke: (tokens && (bracket ? tokens.color.accent : tokens.color.ink)) || '', width: bracket ? 1.5 : 1.3, tile: null },
    // A row whose download failed says why in its channel line, and Enter tries again (ruling DS2ESKWX).
    retry: (reason) => (bracket ? `DOWNLOAD FAILED · ${reason} · ${m('↵')} RETRY` : `download failed · ${reason} · ↵ retry`),
    retryColor: plain ? tint.errInk : bracket ? TINT.warn : (tokens && tokens.color.danger) || '',
    fieldRadius: plain ? 14 : 0,
    rowRadius: plain ? 10 : 0,
    ruleDashed: bracket,
    tint,
  });
}
