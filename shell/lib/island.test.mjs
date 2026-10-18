import { test } from 'node:test';
import assert from 'node:assert/strict';
import { pick, islandText, boxWidth, MAX_WIDTH, monthGrid, shiftMonth } from './island.mjs';

const AT = new Date(2026, 9, 18, 14, 32);
const note = { app: 'notify-send', summary: 'hi', body: '' };
const question = { id: 'Q1', text: 'Import the feed?', options: ['Import now', 'Later'] };

test('with nothing live the island rests', () => {
  assert.equal(pick({}), 'rest');
});

test('a question outranks every other slot', () => {
  const all = { question, calendar: true, notification: note, recording: '00:12', osd: { kind: 'volume', value: 40 }, toast: 'Captured', playing: { title: 'Track', artist: 'Artist' } };
  assert.equal(pick(all), 'question');
});

test('below a question: notification, recording, osd, toast, then playing', () => {
  const slots = { notification: note, recording: '00:12', osd: { kind: 'volume', value: 40 }, toast: 'Captured', playing: { title: 'T', artist: 'A' } };
  const order = [];
  for (const k of ['notification', 'recording', 'osd', 'toast', 'playing']) {
    order.push(pick(slots));
    delete slots[k];
  }
  assert.deepEqual(order, ['notification', 'recording', 'osd', 'toast', 'playing']);
  assert.equal(pick(slots), 'rest');
});

test('the calendar opened from rest gives way only to a question', () => {
  assert.equal(pick({ calendar: true, notification: note }), 'calendar');
  assert.equal(pick({ calendar: true, question }), 'question');
});

test('each mode reads as one line of text', () => {
  assert.equal(islandText('rest', {}, AT), '14:32');
  assert.equal(islandText('rest', { notice: 'theme broken: invalid theme.toml' }, AT), 'theme broken: invalid theme.toml');
  assert.equal(islandText('notification', { notification: { app: 'mail', summary: 'hi', body: 'see you' } }, AT), 'mail · hi · see you');
  assert.equal(islandText('notification', { notification: note }, AT), 'notify-send · hi');
  assert.equal(islandText('osd', { osd: { kind: 'volume', value: 45 } }, AT), 'Volume 45%');
  assert.equal(islandText('osd', { osd: { kind: 'brightness', value: 70 } }, AT), 'Brightness 70%');
  assert.equal(islandText('playing', { playing: { title: 'Track', artist: 'Artist' } }, AT), 'Track — Artist  14:32');
  assert.equal(islandText('playing', { playing: { title: 'Track', artist: '' } }, AT), 'Track  14:32');
  assert.equal(islandText('question', { question }, AT), 'Import the feed?  [1] Import now  [2] Later');
  assert.equal(islandText('toast', { toast: 'Captured' }, AT), 'Captured');
  assert.equal(islandText('recording', { recording: '00:12' }, AT), '● 00:12');
});

test('the box never grows past 560 px', () => {
  assert.equal(MAX_WIDTH, 560);
  assert.equal(boxWidth(100), 100);
  assert.equal(boxWidth(5000), 560);
});

test('the month grid starts on Monday and pads the first and last weeks', () => {
  const g = monthGrid(2026, 9);
  assert.equal(g.title, 'October 2026');
  assert.deepEqual(g.weeks[0], [null, null, null, 1, 2, 3, 4]);
  assert.deepEqual(g.weeks.at(-1), [26, 27, 28, 29, 30, 31, null]);
  assert.equal(g.weeks.length, 5);
  assert.deepEqual(g.cells, [].concat(...g.weeks));
});

test('a month that starts on Sunday puts the 1st last in its first week', () => {
  assert.deepEqual(monthGrid(2026, 1).weeks[0], [null, null, null, null, null, null, 1]);
  assert.deepEqual(monthGrid(2026, 1).weeks.at(-1).slice(0, 6), [23, 24, 25, 26, 27, 28]);
});

test('the calendar reads as its month, and moving a month crosses the year', () => {
  assert.equal(islandText('calendar', { calendar: { year: 2026, month: 9 } }, AT), 'October 2026');
  assert.deepEqual(shiftMonth(2026, 11, 1), { year: 2027, month: 0 });
  assert.deepEqual(shiftMonth(2026, 0, -1), { year: 2025, month: 11 });
});
