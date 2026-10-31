// The Queue, an audio-only mpv the YouTube App drives over its JSON IPC socket: its state read from mpv's events, the now-playing line, and the commands the App sends. Kept pure so node can test it.
import { duration } from './youtube.mjs';

// The reply to the items get on connect carries this id, so the reducer can tell it from the observe replies.
const ITEMS_REQUEST = 1;
const ITEMS = 'user-data/youtube';

const line = (command) => JSON.stringify({ command });
const isObject = (v) => v !== null && typeof v === 'object' && !Array.isArray(v);
const watch = (id) => `https://www.youtube.com/watch?v=${id}`;

// asked counts the items asked for while the Queue read stopped, until mpv reports one playing; items is mpv's user-data by video id.
export const initial = () => ({ pos: -1, count: 0, paused: false, time: null, loop: false, idle: true, path: '', title: '', channel: '', secs: null, items: {}, asked: 0 });

// user-data/youtube is observed too, so a row the App just loaded shows its channel without a reconnect.
export const connectLines = () => [
  ...['playlist-pos', 'playlist-count', 'pause', 'time-pos', 'loop-playlist', 'idle-active', 'path', 'media-title', ITEMS].map((name, i) => line(['observe_property', i + 1, name])),
  JSON.stringify({ command: ['get_property', ITEMS], request_id: ITEMS_REQUEST }),
];

// mpv knows only the URL that plays, so channel and seconds come from the item stored under its video id.
function current(state) {
  const m = /[?&]v=([A-Za-z0-9_-]{11})/.exec(state.path);
  const item = m && isObject(state.items[m[1]]) ? state.items[m[1]] : {};
  return Object.assign(state, { channel: typeof item.channel === 'string' ? item.channel : '', secs: typeof item.secs === 'number' ? item.secs : null });
}

// mpv sends a property it cannot read (path while idle, time-pos before a file loads) with no data at all.
const PROPS = {
  'playlist-pos': (v) => ({ pos: typeof v === 'number' ? v : -1 }),
  'playlist-count': (v) => ({ count: typeof v === 'number' ? v : 0 }),
  pause: (v) => ({ paused: v === true }),
  'time-pos': (v) => ({ time: typeof v === 'number' ? v : null }),
  'loop-playlist': (v) => ({ loop: v !== undefined && v !== null && v !== false && v !== 'no' }),
  // An item playing means the asks have reached mpv, so the next a on a Queue that ends replaces it.
  'idle-active': (v) => (v === false ? { idle: false, asked: 0 } : { idle: true }),
  path: (v) => ({ path: typeof v === 'string' ? v : '' }),
  'media-title': (v) => ({ title: typeof v === 'string' ? v : '' }),
  [ITEMS]: (v) => ({ items: isObject(v) ? v : {} }),
};

export function reduce(state, text) {
  let msg;
  try {
    msg = JSON.parse(text);
  } catch (e) {
    return state;
  }
  if (!isObject(msg)) return state;
  if (msg.event === 'property-change' && PROPS[msg.name]) return current(Object.assign({}, state, PROPS[msg.name](msg.data)));
  // A fresh mpv has no user-data yet and answers the get with an error and no data.
  if (msg.request_id === ITEMS_REQUEST) return current(Object.assign({}, state, { items: isObject(msg.data) ? msg.data : {} }));
  return state;
}

export function nowLine(state) {
  if (state.idle || state.count <= 0 || state.pos < 0) return '';
  const left = state.count - state.pos - 1;
  return (
    `${state.paused ? '⏸' : '▶'} ${state.title}` +
    (state.channel ? ` — ${state.channel}` : '') +
    ` · ${duration(state.time === null ? 0 : state.time)}` +
    (state.secs === null ? '' : ` / ${duration(state.secs)}`) +
    (left > 0 ? ` · +${left}` : '')
  );
}

const stopped = (state) => state.idle || state.count === 0;

// a starts a stopped Queue afresh rather than adding to the entries of one that ended, but only the first ask does, or a fast second press would replace the first.
export function itemLines(state, row, how) {
  const mode = how === 'play' || (stopped(state) && state.asked === 0) ? 'replace' : 'append-play';
  return [
    line(['set_property', `${ITEMS}/${row.id}`, { title: row.title, channel: row.channel, secs: row.secs }]),
    line(['loadfile', watch(row.id), mode, -1, { 'force-media-title': row.title }]),
  ];
}

// The App calls this after each itemLines, since mpv reports nothing back before the next press can come.
export const asked = (state) => (stopped(state) ? Object.assign({}, state, { asked: state.asked + 1 }) : state);

export const setPauseLine = (paused) => line(['set_property', 'pause', paused]);
export const pauseLine = (state) => setPauseLine(!state.paused);
export const repeatLine = (state) => line(['set_property', 'loop-playlist', state.loop ? 'no' : 'inf']);

// The start buffer: lines sent while the unit starts wait here, and the caller starts the unit once.
export const link = () => ({ status: 'down', pending: [] });

export function send(l, lines) {
  if (l.status === 'up') return { link: l, write: lines, start: false };
  return { link: { status: 'starting', pending: [...l.pending, ...lines] }, write: [], start: l.status === 'down' };
}

export const connected = (l) => ({ link: { status: 'up', pending: [] }, write: l.pending });

// The socket closed or the unit failed to start: what waited is dropped, and the next send starts the unit again.
export const lost = () => link();
