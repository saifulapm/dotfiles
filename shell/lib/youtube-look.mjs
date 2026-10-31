// How the YouTube App reads under a token set, as the three themes' YouTube boards draw it: the title strip, the sidebar, the field and chips, the legend and the empty views.
import { listLook } from './voice.mjs';
import { EMPTY } from './youtube.mjs';

// The boards' tints, which no token carries: Paper's chosen place and row rule, Artboard's accent tint, field, tiles and thumbnail; one set for all voices, as a theme switch can draw a voice's branch before its look lands.
const TINT = { chosen: '#EFE6D2', rule: '#D8CDB6', tint: '#EEF1FF', deep: '#2638C9', tile: '#F2F3F6', field: '#F6F7F9', thumb: '#E9ECF1' };

const SEARCH_KEYS = [['j/k', 'move'], ['↵', 'play video'], ['m', 'play audio'], ['a', 'add to queue'], ['s', 'save'], ['p', 'add to playlist'], ['d/D', 'download audio/video'], ['/', 'search'], ['tab', 'sidebar'], ['esc', 'back']];
// Blueprint marks the shifted key and spaces the slash in its download pair.
const BRACKET_DOWNLOAD = { key: '[D/⇧D]', word: 'DOWNLOAD AUDIO / VIDEO' };
const EMPTY_KEYS = [['/', 'search'], ['tab', 'sidebar'], ['esc', 'back']];

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
    repeat: bracket ? 'REPEAT OFF' : 'repeat off',
    legend(view) {
      const keys = l.keys(view === 'search' ? SEARCH_KEYS : EMPTY_KEYS);
      return bracket ? keys.map((k) => (k.word === 'DOWNLOAD AUDIO/VIDEO' ? BRACKET_DOWNLOAD : k)) : keys;
    },
    empty(view) {
      if (view === 'saved') return { head: EMPTY.saved.head, key: EMPTY.saved.key, rest: EMPTY.saved.rest };
      if (view === 'history') return { head: '', key: '', rest: 'Enter or m plays a video' };
      return null;
    },
    fieldRadius: plain ? 14 : 0,
    rowRadius: plain ? 10 : 0,
    ruleDashed: bracket,
    tint: TINT,
  });
}
