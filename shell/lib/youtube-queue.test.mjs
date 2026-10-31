import { test } from 'node:test';
import assert from 'node:assert/strict';
import * as Q from './youtube-queue.mjs';

const ARUARIAN = { id: 'fakeVid0001', title: 'Aruarian Dance', channel: 'Nujabes - Topic', duration: '4:27', secs: 267, thumb: 'fakeVid0001' };
const FEATHER = { id: 'fakeVid0002', title: 'Feather', channel: 'Nujabes', duration: '2:55', secs: 175, thumb: '' };
const watch = (id) => `https://www.youtube.com/watch?v=${id}`;
const ev = (name, data) => JSON.stringify(data === undefined ? { event: 'property-change', id: 1, name } : { event: 'property-change', id: 1, name, data });
const feed = (state, lines) => lines.reduce(Q.reduce, state);
const loadMode = (line) => JSON.parse(line).command[2];

// One item playing, as mpv reports it once m has loaded the fake CLI's first row.
const playing = (over) =>
  Object.assign(Q.initial(), { pos: 0, count: 1, idle: false, time: 0, path: watch('fakeVid0001'), title: 'Aruarian Dance', channel: 'Nujabes - Topic', secs: 267 }, over);

test('a fresh Queue reads idle with nothing in it', () => {
  const s = Q.initial();
  for (const [k, v] of Object.entries({ pos: -1, count: 0, paused: false, time: null, loop: false, idle: true, path: '', title: '', channel: '', secs: null })) assert.equal(s[k], v, k);
});

test('the line reads the playing title, channel and both clocks, with no +N on the last item', () => {
  assert.equal(Q.nowLine(playing()), '▶ Aruarian Dance — Nujabes - Topic · 0:00 / 4:27');
});

test('two items after the current one end the line with +2', () => {
  assert.equal(Q.nowLine(playing({ count: 3, time: 72.6 })), '▶ Aruarian Dance — Nujabes - Topic · 1:12 / 4:27 · +2');
});

test('a paused Queue reads ⏸', () => {
  assert.equal(Q.nowLine(playing({ paused: true })), '⏸ Aruarian Dance — Nujabes - Topic · 0:00 / 4:27');
});

test('an unknown channel and duration leave their parts out, and no time reads 0:00', () => {
  assert.equal(Q.nowLine(playing({ channel: '', secs: null, time: null })), '▶ Aruarian Dance · 0:00');
});

test('no Queue, and a Queue whose playlist ended, read an empty line', () => {
  assert.equal(Q.nowLine(Q.initial()), '');
  assert.equal(Q.nowLine(playing({ idle: true, pos: -1, count: 1, path: '', title: '', time: null })), '');
});

test('the lines sent on connect observe the Queue and ask for the items mpv keeps', () => {
  const sent = Q.connectLines().map((l) => JSON.parse(l));
  const observed = sent.filter((c) => c.command[0] === 'observe_property').map((c) => c.command[2]);
  for (const name of ['playlist-pos', 'playlist-count', 'pause', 'time-pos', 'loop-playlist', 'idle-active', 'path', 'media-title']) assert.ok(observed.includes(name), name);
  const get = sent.filter((c) => c.command[0] === 'get_property');
  assert.deepEqual(get.map((c) => c.command[1]), ['user-data/youtube']);
  assert.equal(typeof get[0].request_id, 'number');
});

// The lines are mpv 0.41's own, from a reopened App reading a Queue of two at its first item.
test('a reopened App reads the running Queue from the replies and events mpv sends', () => {
  const get = JSON.parse(Q.connectLines().find((l) => l.includes('get_property')));
  const s = feed(Q.initial(), [
    '{"request_id":0,"error":"success"}',
    JSON.stringify({ request_id: get.request_id, error: 'success', data: { fakeVid0001: { title: 'Aruarian Dance', channel: 'Nujabes - Topic', secs: 267 }, fakeVid0002: { title: 'Feather', channel: 'Nujabes', secs: 175 } } }),
    ev('playlist-pos', 0),
    ev('idle-active', false),
    ev('path', watch('fakeVid0001')),
    ev('playlist-count', 2),
    ev('media-title', 'Aruarian Dance'),
    ev('loop-playlist', 'inf'),
    ev('pause', true),
    '{"event":"audio-reconfig"}',
    ev('time-pos', 72.6),
  ]);
  const { pos, count, paused, time, loop, idle, path, title, channel, secs } = s;
  assert.deepEqual(
    { pos, count, paused, time, loop, idle, path, title, channel, secs },
    { pos: 0, count: 2, paused: true, time: 72.6, loop: true, idle: false, path: watch('fakeVid0001'), title: 'Aruarian Dance', channel: 'Nujabes - Topic', secs: 267 },
  );
  assert.equal(Q.nowLine(s), '⏸ Aruarian Dance — Nujabes - Topic · 1:12 / 4:27 · +1');
});

test('a fresh mpv answers the items get with an error and reports missing values with no data', () => {
  const get = JSON.parse(Q.connectLines().find((l) => l.includes('get_property')));
  const s = feed(playing(), [
    JSON.stringify({ request_id: get.request_id, error: 'property not found' }),
    ev('playlist-pos', -1),
    ev('idle-active', true),
    ev('path'),
    ev('media-title'),
    ev('time-pos'),
    ev('loop-playlist', false),
  ]);
  assert.deepEqual([s.pos, s.idle, s.path, s.title, s.time, s.loop, s.channel, s.secs], [-1, true, '', '', null, false, '', null]);
});

// mpv sends the user-data change before the path change, and skips an unavailable item by itself.
test('the channel and seconds follow the current item, through a user-data change and a skip', () => {
  const s = feed(Q.initial(), [
    ev('user-data/youtube', { fakeVid0001: { title: 'Aruarian Dance', channel: 'Nujabes - Topic', secs: 267 } }),
    ev('path', watch('fakeVid0001')),
  ]);
  assert.deepEqual([s.channel, s.secs], ['Nujabes - Topic', 267]);
  const next = feed(s, [ev('user-data/youtube', { fakeVid0001: { title: 'Aruarian Dance', channel: 'Nujabes - Topic', secs: 267 }, fakeVid0002: { title: 'Feather', channel: 'Nujabes', secs: 175 } }), ev('path', watch('fakeVid0002')), ev('media-title', 'Feather')]);
  assert.deepEqual([next.title, next.channel, next.secs], ['Feather', 'Nujabes', 175]);
});

test('bad JSON and lines the Queue does not read change nothing', () => {
  const s = playing();
  for (const line of ['{"event":"property-change","name":"pau', '', 'null', '[1]', '{"event":"start-file","playlist_entry_id":1}', '{"request_id":0,"error":"success"}']) assert.deepEqual(Q.reduce(s, line), s, line);
});

test('m stores the row in mpv, then replaces the Queue with it titled as the row', () => {
  assert.deepEqual(Q.itemLines(playing({ count: 3 }), ARUARIAN, 'play').map((l) => JSON.parse(l)), [
    { command: ['set_property', 'user-data/youtube/fakeVid0001', { title: 'Aruarian Dance', channel: 'Nujabes - Topic', secs: 267 }] },
    { command: ['loadfile', watch('fakeVid0001'), 'replace', -1, { 'force-media-title': 'Aruarian Dance' }] },
  ]);
});

test('a appends to a running Queue, and replaces a stopped or empty one', () => {
  assert.deepEqual(Q.itemLines(playing(), FEATHER, 'add').map((l) => JSON.parse(l))[1], { command: ['loadfile', watch('fakeVid0002'), 'append-play', -1, { 'force-media-title': 'Feather' }] });
  const ended = playing({ idle: true, pos: -1, count: 3, path: '', title: '' });
  assert.equal(loadMode(Q.itemLines(ended, FEATHER, 'add')[1]), 'replace');
  assert.equal(loadMode(Q.itemLines(Q.initial(), FEATHER, 'add')[1]), 'replace');
});

// Each press is asked for before mpv reports anything back, so the state still reads idle for all of them.
test('m then a fast a on a stopped Queue replace once and append once', () => {
  let s = Q.initial();
  const modes = [];
  for (const [row, how] of [[ARUARIAN, 'play'], [FEATHER, 'add']]) {
    modes.push(loadMode(Q.itemLines(s, row, how)[1]));
    s = Q.asked(s);
  }
  assert.deepEqual(modes, ['replace', 'append-play']);
});

test('once an item plays, the asks are forgotten, so a Queue that ends replaces again', () => {
  let s = Q.asked(Q.initial());
  s = feed(s, [ev('idle-active', false), ev('playlist-count', 1), ev('playlist-pos', 0)]);
  s = Q.asked(s);
  s = feed(s, [ev('playlist-pos', -1), ev('idle-active', true)]);
  assert.equal(loadMode(Q.itemLines(s, FEATHER, 'add')[1]), 'replace');
});

test('the link writes at once while up', () => {
  const up = Q.connected(Q.link()).link;
  assert.deepEqual(Q.send(up, ['x', 'y']), { link: up, write: ['x', 'y'], start: false });
});

test('a pressed 20 times with no Queue starts one unit and sends 20 adds in order, one replace then 19 appends', () => {
  const rows = Array.from({ length: 20 }, (_, i) => ({ id: `fakeVid${String(i).padStart(4, '0')}`, title: `Song ${i}`, channel: 'Nujabes', secs: 200 }));
  let s = Q.initial();
  let link = Q.link();
  let starts = 0;
  for (const row of rows) {
    const lines = Q.itemLines(s, row, 'add');
    s = Q.asked(s);
    const r = Q.send(link, lines);
    assert.deepEqual(r.write, []);
    if (r.start) starts++;
    link = r.link;
  }
  assert.equal(starts, 1);
  assert.equal(link.status, 'starting');
  const done = Q.connected(link);
  assert.deepEqual(done.link, { status: 'up', pending: [] });
  assert.equal(done.write.length, 40);
  const loads = done.write.map((l) => JSON.parse(l).command).filter((c) => c[0] === 'loadfile');
  assert.deepEqual(loads.map((c) => c[1]), rows.map((r) => watch(r.id)));
  assert.deepEqual(loads.map((c) => c[2]), ['replace', ...Array(19).fill('append-play')]);
});

test('a lost socket drops what was pending, and the next send starts the unit again', () => {
  const r = Q.send(Q.link(), ['x']);
  assert.equal(r.start, true);
  const down = Q.lost(r.link);
  assert.deepEqual(down, { status: 'down', pending: [] });
  const again = Q.send(down, ['y']);
  assert.deepEqual(again, { link: { status: 'starting', pending: ['y'] }, write: [], start: true });
});

test('Space toggles pause, a video sets it, and r toggles repeat between inf and no', () => {
  assert.deepEqual(JSON.parse(Q.pauseLine(playing())), { command: ['set_property', 'pause', true] });
  assert.deepEqual(JSON.parse(Q.pauseLine(playing({ paused: true }))), { command: ['set_property', 'pause', false] });
  assert.deepEqual(JSON.parse(Q.setPauseLine(true)), { command: ['set_property', 'pause', true] });
  assert.deepEqual(JSON.parse(Q.repeatLine(playing())), { command: ['set_property', 'loop-playlist', 'inf'] });
  assert.deepEqual(JSON.parse(Q.repeatLine(playing({ loop: true }))), { command: ['set_property', 'loop-playlist', 'no'] });
});
