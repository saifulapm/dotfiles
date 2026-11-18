import { test } from 'node:test';
import assert from 'node:assert/strict';
import { TILES, WIDTH, move, tiles, height, leftText, TILE_OF, PAGES } from './control-home.mjs';

const base = { wifi: null, wifiOn: true, bt: null, btOn: true, sink: null, panel: null, recordingMs: 0, battery: null, units: {}, dnd: false, awakeUntil: 0, now: 1000 };

test('every row of tiles fills the 608 px between the island edges', () => {
  for (const r of [1, 2, 3, 4]) {
    const row = TILES.filter((t) => t.row === r);
    const last = row[row.length - 1];
    assert.equal(row[0].x, 0);
    assert.equal(Math.round(last.x + last.w), WIDTH);
  }
  assert.equal(height(), 52 + 60 + 56 + 60 + 48 + 4 * 8);
});

test('from Wi-Fi, l is Bluetooth and j is the Brightness row below', () => {
  assert.equal(move('wifi', 1, 0), 'bluetooth');
  assert.equal(move('wifi', 0, 1), 'brightness');
  assert.equal(move('wifi', 0, -1), 'calendar');
  assert.equal(move('wifi', -1, 0), 'wifi');
  assert.equal(move('sound', 1, 0), 'sound');
});

test('j and k land on the nearest tile of the next row and stop at the ends', () => {
  assert.equal(move('brightness', 0, 1), 'battery');
  assert.equal(move('sync', 0, 1), 'lock');
  assert.equal(move('record', 0, 1), 'dnd');
  assert.equal(move('power', 0, 1), 'power');
  assert.equal(move('calendar', 0, -1), 'calendar');
  assert.equal(move('lock', 0, -1), 'sync');
});

test('the tiles keep their titles in board order whatever they read', () => {
  assert.deepEqual(
    tiles(base).map((t) => t.title),
    ['Wi-Fi', 'Bluetooth', 'Sound', 'Brightness', 'Record screen', 'Battery', 'Sync', 'Do Not Disturb', 'Stay awake', 'Lock', 'Power'],
  );
});

test('a connected network inverts the Wi-Fi tile and names it', () => {
  const w = tiles({ ...base, wifi: { name: 'Dots Home', signal: 94 } })[0];
  assert.equal(w.on, true);
  assert.equal(w.label, 'Dots Home');
  assert.equal(w.detail, '94%');
  const off = tiles(base)[0];
  assert.equal(off.on, false);
  assert.equal(off.label, 'Wi-Fi');
});

test('Do Not Disturb and Stay awake are on only while they hold', () => {
  const t = tiles({ ...base, dnd: true, awakeUntil: 5000 });
  assert.equal(t.find((x) => x.id === 'dnd').on, true);
  assert.equal(t.find((x) => x.id === 'awake').on, true);
  const later = tiles({ ...base, awakeUntil: 500 });
  assert.equal(later.find((x) => x.id === 'awake').on, false);
});

test('a failing sync unit makes the Sync tile danger, and Power is always danger', () => {
  const t = tiles({ ...base, units: { mail: { ok: false, error: 'x' }, notes: { ok: true } } });
  assert.equal(t.find((x) => x.id === 'sync').danger, true);
  assert.equal(t.find((x) => x.id === 'sync').detail, '1 failing');
  assert.equal(t.find((x) => x.id === 'power').danger, true);
});

test('a recording counts on the Record screen tile', () => {
  const r = tiles({ ...base, recordingMs: 61500 }).find((x) => x.id === 'record');
  assert.equal(r.on, true);
  assert.equal(r.detail, '01:01');
});

test('a muted sink draws an empty slider', () => {
  const s = tiles({ ...base, sink: { name: 'Speakers', volume: 0.6, muted: true } }).find((x) => x.id === 'sound');
  assert.equal(s.level, 0);
});

test('time left reads as board 4 words it', () => {
  assert.equal(leftText(9600), '2 h 40 min');
  assert.equal(leftText(2400), '40 min');
  assert.equal(leftText(0), '');
});

test('each page returns to a tile that opens it', () => {
  for (const [page, tile] of Object.entries(TILE_OF)) assert.equal(PAGES[tile], page);
});
