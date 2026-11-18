// Control's Home in the island (board 4): where each tile sits, how hjkl moves between them, what each one reads and what Enter on it does.
import { clockText } from './margins.mjs';

// The island is 640 px wide with 16 px inside, so the tiles share 608 px, 8 px apart.
export const WIDTH = 608;
export const GAP = 8;
// Each row's height: the clock, Wi-Fi to Sound, Brightness, Record screen to Sync, the switches and buttons.
export const ROWS = [52, 60, 56, 60, 48];
const third = (WIDTH - 2 * GAP) / 3;
const half = (WIDTH - 3 * GAP - 2 * 48) / 2;

// Every focusable place on Home, by row, with its left edge and width; the clock's date and "Calendar" are the first.
export const TILES = [
  { id: 'calendar', row: 0, x: 0, w: WIDTH },
  { id: 'wifi', row: 1, x: 0, w: third },
  { id: 'bluetooth', row: 1, x: third + GAP, w: third },
  { id: 'sound', row: 1, x: 2 * (third + GAP), w: third },
  { id: 'brightness', row: 2, x: 0, w: WIDTH },
  { id: 'record', row: 3, x: 0, w: third },
  { id: 'battery', row: 3, x: third + GAP, w: third },
  { id: 'sync', row: 3, x: 2 * (third + GAP), w: third },
  { id: 'dnd', row: 4, x: 0, w: half },
  { id: 'awake', row: 4, x: half + GAP, w: half },
  { id: 'lock', row: 4, x: 2 * (half + GAP), w: 48 },
  { id: 'power', row: 4, x: 2 * (half + GAP) + 48 + GAP, w: 48 },
];

export const TITLES = {
  wifi: 'Wi-Fi',
  bluetooth: 'Bluetooth',
  sound: 'Sound',
  brightness: 'Brightness',
  record: 'Record screen',
  battery: 'Battery',
  sync: 'Sync',
  dnd: 'Do Not Disturb',
  awake: 'Stay awake',
  lock: 'Lock',
  power: 'Power',
};

// Enter on a tile opens the section it stands for, as a page; the rest act in place.
export const PAGES = { wifi: 'wifi', bluetooth: 'bluetooth', sound: 'audio', brightness: 'display', battery: 'power', sync: 'route', power: 'power' };

// The tile a page returns to, so Esc lands back where Enter was pressed.
export const TILE_OF = { wifi: 'wifi', bluetooth: 'bluetooth', audio: 'sound', display: 'brightness', power: 'battery', route: 'sync' };

export const rowTop = (row) => ROWS.slice(0, row).reduce((t, h) => t + h + GAP, 0);
export const height = () => rowTop(ROWS.length - 1) + ROWS[ROWS.length - 1];

const centre = (t) => t.x + t.w / 2;

// h and l move along the row and stop at its ends; j and k move to the row above or below, onto the tile whose centre is nearest.
export function move(id, dx, dy) {
  const at = TILES.find((t) => t.id === id) ?? TILES[1];
  if (dx) {
    const row = TILES.filter((t) => t.row === at.row);
    const i = row.indexOf(at) + dx;
    return row[Math.max(0, Math.min(row.length - 1, i))].id;
  }
  const r = at.row + dy;
  const row = TILES.filter((t) => t.row === r);
  if (row.length === 0) return at.id;
  return row.reduce((best, t) => (Math.abs(centre(t) - centre(at)) < Math.abs(centre(best) - centre(at)) ? t : best)).id;
}

// What each tile reads, from the plain state Control gathers: { wifi: {name, signal} | null, wifiOn, bt: {name, battery} | null, btOn, sink: {name, volume, muted} | null, panel: percent | null, recordingMs, battery: {percent, state, profile, left} | null, units, dnd, awakeUntil, now }.
export function tiles(s) {
  const failing = Object.keys(s.units ?? {}).filter((k) => s.units[k].ok === false);
  const btDetail = s.bt ? s.bt.name + (s.bt.battery !== null && s.bt.battery !== undefined ? ' · ' + s.bt.battery + '%' : '') : s.btOn ? 'On' : 'Off';
  const sec = Math.floor((s.recordingMs ?? 0) / 1000);
  const pad = (n) => String(n).padStart(2, '0');
  const b = s.battery;
  const t = (id, label, detail, on, extra) => Object.assign({ id, title: TITLES[id], label, detail, on }, extra ?? {});
  return [
    t('wifi', s.wifi ? s.wifi.name : 'Wi-Fi', s.wifi ? s.wifi.signal + '%' : s.wifiOn ? 'Not connected' : 'Off', !!s.wifi),
    t('bluetooth', 'Bluetooth', btDetail, !!s.bt),
    t('sound', 'Sound', s.sink ? s.sink.name : 'No output', false, { level: s.sink && !s.sink.muted ? s.sink.volume : 0 }),
    t('brightness', 'Brightness', s.panel === null || s.panel === undefined ? '' : s.panel + '%', false, { level: s.panel === null || s.panel === undefined ? 0 : s.panel / 100 }),
    t('record', 'Record screen', pad(Math.floor(sec / 60)) + ':' + pad(sec % 60), s.recordingMs > 0),
    t('battery', b ? b.percent + '%' : 'Battery', b ? [b.profile, b.left].filter((x) => x).join(' · ') : 'No battery', false),
    t('sync', 'Sync', failing.length ? failing.length + ' failing' : Object.keys(s.units ?? {}).length ? 'ok' : 'no rounds yet', false, { danger: failing.length > 0 }),
    t('dnd', 'Do Not Disturb', '', !!s.dnd),
    t('awake', 'Stay awake', s.awakeUntil > s.now ? 'until ' + clockText(new Date(s.awakeUntil)) : '', s.awakeUntil > s.now),
    t('lock', 'Lock', '', false),
    t('power', 'Power', '', false, { danger: true }),
  ];
}

// A battery's time left as board 4 words it: "2 h 40 min", "40 min", or "" when UPower has none.
export function leftText(seconds) {
  if (!(seconds > 0)) return '';
  const m = Math.round(seconds / 60);
  const h = Math.floor(m / 60);
  return h > 0 ? `${h} h ${m % 60} min` : `${m} min`;
}
