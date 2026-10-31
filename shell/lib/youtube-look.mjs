// How the YouTube App reads under a token set, as the three themes' YouTube boards draw it: the title strip, the sidebar, the field and chips, the legend, the empty views and the error block.
import { listLook } from './voice.mjs';
import { EMPTY } from './youtube.mjs';

// The boards' tints, which no token carries: Paper's chosen place, row rule and light ink on a lit row, Artboard's accent tint, field, tiles, thumbnail and error block, Blueprint's warning amber; one set for all voices, as a theme switch can draw a voice's branch before its look lands.
const TINT = { chosen: '#EFE6D2', rule: '#D8CDB6', onInk: '#D9CFBB', tint: '#EEF1FF', deep: '#2638C9', tile: '#F2F3F6', field: '#F6F7F9', thumb: '#E9ECF1', errFill: '#FFF1E8', errInk: '#B4380B', errText: '#2B2F36', warn: '#FFB547' };

const SEARCH_KEYS = [['j/k', 'move'], ['↵', 'play video'], ['m', 'play audio'], ['a', 'add to queue'], ['s', 'save'], ['p', 'add to playlist'], ['d/D', 'download audio/video'], ['/', 'search'], ['tab', 'sidebar'], ['esc', 'back']];
// Blueprint marks the shifted key and spaces the slash in its download pair.
const BRACKET_DOWNLOAD = { key: '[D/⇧D]', word: 'DOWNLOAD AUDIO / VIDEO' };
const EMPTY_KEYS = [['/', 'search'], ['tab', 'sidebar'], ['esc', 'back']];
const FAILED_KEYS = [['↵', 'try again']].concat(EMPTY_KEYS);

const PLACES = [
  { view: 'search', name: 'Search' },
  { view: 'saved', name: 'Saved' },
  { view: 'history', name: 'History' },
];

export function youtubeLook(tokens) {
  const l = listLook(tokens);
  const voice = l.voice;
  const plain = voice === 'plain';
  const bracket = voice === 'bracket';
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
    hint: bracket ? '[/]' : '/',
    typeLabel: plain ? '' : 'TYPE',
    chips: ['Videos', 'Playlists', 'Channels'].map((w) => (bracket ? w.toUpperCase() : w)),
    results: plain ? 'Results' : 'RESULTS',
    // The now-playing line's right side, as the Queue's loop-playlist reads.
    repeat: (on) => (bracket ? (on ? 'REPEAT ON' : 'REPEAT OFF') : on ? 'repeat on' : 'repeat off'),
    // A failed search's list is its error block, so only try again and the moves away act on it.
    legend(view, failed) {
      const keys = l.keys(view !== 'search' ? EMPTY_KEYS : failed ? FAILED_KEYS : SEARCH_KEYS);
      return bracket ? keys.map((k) => (k.word === 'DOWNLOAD AUDIO/VIDEO' ? BRACKET_DOWNLOAD : k)) : keys;
    },
    empty(view) {
      if (view === 'saved') return { head: EMPTY.saved.head, key: EMPTY.saved.key, rest: EMPTY.saved.rest };
      if (view === 'history') return { head: '', key: '↵', rest: 'or m plays a video' };
      if (view === 'channel') return { head: 'No videos on this channel', key: '', rest: '' };
      return null;
    },
    failed: {
      head: "YouTube didn't give results",
      key: bracket ? '[↵]' : '↵',
      word: 'try again',
      // Paper's board heads a stale yt-dlp's block YOUTUBE CHANGED; the other kinds' boards draw no such line.
      kicker: (kind) => (voice === 'caps' && kind === 'extraction' ? 'YOUTUBE CHANGED' : ''),
    },
    fieldRadius: plain ? 14 : 0,
    rowRadius: plain ? 10 : 0,
    ruleDashed: bracket,
    tint: TINT,
  });
}
