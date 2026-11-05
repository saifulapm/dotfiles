// The Queue, an audio-only mpv the YouTube App drives over its JSON IPC socket: its state read from mpv's events, the now-playing line, and the commands the App sends. Kept pure so node can test it.
import { duration } from './youtube.mjs';

// The reply to the items get on connect carries this id, so the reducer can tell it from the observe replies.
const ITEMS_REQUEST = 1;
const ITEMS = 'user-data/youtube';
// Set by the App when it loads a shuffled playlist, so a reopened App still reads the Queue as shuffled.
const SHUFFLED = 'user-data/youtube-shuffled';

const line = (command) => JSON.stringify({ command });
const isObject = (v) => v !== null && typeof v === 'object' && !Array.isArray(v);
const watch = (id) => `https://www.youtube.com/watch?v=${id}`;
// A downloaded row plays its file, by files {id: path} as youtube-get.mjs playFiles gives them; any other streams.
const target = (id, files) => (files && typeof files[id] === 'string' ? files[id] : watch(id));

// asked counts the items asked for while the Queue read stopped, until mpv reports one playing; items is mpv's user-data by video id.
export const initial = () => ({ pos: -1, count: 0, paused: false, time: null, loop: false, idle: true, path: '', title: '', channel: '', secs: null, items: {}, asked: 0, shuffled: false });

// user-data/youtube is observed too, so a row the App just loaded shows its channel without a reconnect.
export const connectLines = () => [
  ...['playlist-pos', 'playlist-count', 'pause', 'time-pos', 'loop-playlist', 'idle-active', 'path', 'media-title', ITEMS, SHUFFLED].map((name, i) => line(['observe_property', i + 1, name])),
  JSON.stringify({ command: ['get_property', ITEMS], request_id: ITEMS_REQUEST }),
];

// mpv knows only the URL or file that plays, so channel and seconds come from the item stored under its video id; a file names it between [ and ] before its extension.
function current(state) {
  const m = /[?&]v=([A-Za-z0-9_-]{11})/.exec(state.path) || /\[([A-Za-z0-9_-]{11})\]\.[A-Za-z0-9]+$/.exec(state.path);
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
  [SHUFFLED]: (v) => ({ shuffled: v === true }),
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
    (left > 0 ? ` · +${left}` : '') +
    (state.shuffled ? ' · shuffled' : '')
  );
}

const stopped = (state) => state.idle || state.count === 0;

// a starts a stopped Queue afresh rather than adding to the entries of one that ended, but only the first ask does, or a fast second press would replace the first.
export function itemLines(state, row, how, files) {
  const mode = how === 'play' || (stopped(state) && state.asked === 0) ? 'replace' : 'append-play';
  const lines = [
    line(['set_property', `${ITEMS}/${row.id}`, { title: row.title, channel: row.channel, secs: row.secs }]),
    line(['loadfile', target(row.id, files), mode, -1, { 'force-media-title': row.title }]),
  ];
  // mpv keeps pause from one file to the next, so a Queue a video paused would load the row paused and stay silent. A single row replacing the Queue is no longer a shuffled playlist.
  return mode === 'replace' ? lines.concat([shuffledLine(false), setPauseLine(false)]) : lines;
}

const shuffledLine = (on) => line(['set_property', SHUFFLED, on]);
const loadable = (rows) => rows.filter((r) => !r.unavailable);

// A whole playlist's rows in order: 'play' replaces the Queue, 'add' appends, and a stopped Queue with no ask yet starts afresh. A row YouTube marks unavailable stays out, since mpv would only skip it.
export const listLines = (state, rows, how, files) => load(state, rows, how, false, files);

function load(state, rows, how, shuffled, files) {
  const list = loadable(rows);
  if (list.length === 0) return [];
  const replace = how === 'play' || (stopped(state) && state.asked === 0);
  const lines = [];
  list.forEach((row, i) => {
    lines.push(line(['set_property', `${ITEMS}/${row.id}`, { title: row.title, channel: row.channel, secs: row.secs }]));
    lines.push(line(['loadfile', target(row.id, files), replace && i === 0 ? 'replace' : 'append-play', -1, { 'force-media-title': row.title }]));
  });
  // Whatever replaces the Queue says whether it is shuffled; an append leaves the flag alone.
  if (replace) lines.push(shuffledLine(shuffled));
  return replace ? lines.concat([setPauseLine(false)]) : lines;
}

// A seeded Mulberry32, so a seed gives the same order twice.
function mulberry32(seed) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

// Fisher-Yates on a copy; a seed that is no finite number draws from Math.random.
export function shuffle(rows, seed) {
  const rand = Number.isFinite(seed) ? mulberry32(seed) : Math.random;
  const out = rows.slice();
  for (let i = out.length - 1; i > 0; i--) {
    const j = Math.floor(rand() * (i + 1));
    [out[i], out[j]] = [out[j], out[i]];
  }
  return out;
}

// S changes the order of what plays: a draw that leaves the loadable rows as they were turns them by one.
export function shuffledLines(state, rows, seed, files) {
  const list = loadable(rows);
  const drawn = shuffle(list, seed);
  const same = drawn.every((r, i) => r === list[i]);
  return load(state, same && list.length > 1 ? list.slice(1).concat(list.slice(0, 1)) : drawn, 'play', true, files);
}

// The App calls this after each itemLines, since mpv reports nothing back before the next press can come.
export const asked = (state) => (stopped(state) ? Object.assign({}, state, { asked: state.asked + 1 }) : state);

export function setPauseLine(paused) {
  return line(['set_property', 'pause', paused]);
}
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
