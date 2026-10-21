import { test } from 'node:test';
import assert from 'node:assert/strict';
import { pick, islandText, boxWidth, MAX_WIDTH, monthGrid, shiftMonth, recordingText, springCurve, islandMotion, isCompact, ease } from './island.mjs';

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

test('below a question: notification, recording, osd, toast, a send, then playing', () => {
  const slots = { notification: note, recording: '00:12', osd: { kind: 'volume', value: 40 }, toast: 'Captured', sending: { count: 2, to: 'nuc', pct: 48 }, playing: { title: 'T', artist: 'A' } };
  const order = [];
  for (const k of ['notification', 'recording', 'osd', 'toast', 'sending', 'playing']) {
    order.push(pick(slots));
    delete slots[k];
  }
  assert.deepEqual(order, ['notification', 'recording', 'osd', 'toast', 'sending', 'playing']);
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
  assert.equal(islandText('recording', { recording: '00:12' }, AT), 'REC 00:12');
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

test('a recording reads minutes and seconds since it started', () => {
  assert.equal(recordingText(1000, 1000), '00:00');
  assert.equal(recordingText(1000, 13999), '00:12');
  assert.equal(recordingText(0, 61 * 60 * 1000), '61:00');
});

// The approved prototype's numbers: stiffness 260 and damping 0.70 open, 1.5 times stiffer and 0.08 more damped close.
test('Artboard: the spring opens in 611 ms and closes in 456 ms', () => {
  const m = islandMotion('spring');
  assert.deepEqual([m.open.ms, m.close.ms], [611, 456]);
  assert.deepEqual(m.swap, { kind: 'blur', inMs: 306, outMs: 130, delay: 60, blur: 6 });
});

test('a spring curve starts at 0, overshoots and ends at rest', () => {
  const { points } = springCurve(260, 0.7);
  assert.equal(points.length, 61);
  assert.deepEqual([points[0], points[60]], [0, 1]);
  assert.ok(points.some((y) => y > 1));
});

test('a critically damped spring never overshoots', () => {
  assert.ok(springCurve(260, 1).points.every((y) => y <= 1));
});

test('Paper is snappy: 120 ms open, 96 ms close, past halfway a quarter of the way in', () => {
  const m = islandMotion('snappy');
  assert.deepEqual([m.open.ms, m.close.ms, m.swap.kind], [120, 96, 'drop']);
  assert.deepEqual([m.open.points[0], m.open.points[60]], [0, 1]);
  assert.ok(ease(m.open.points, 0.25) > 0.5);
});

test('ease reads between samples and keeps the overshoot', () => {
  const linear = islandMotion('linear').open.points;
  assert.deepEqual([ease(linear, 0), ease(linear, 0.5), ease(linear, 1)], [0, 0.5, 1]);
  const spring = springCurve(260, 0.7).points;
  assert.ok([0.3, 0.35, 0.4, 0.45].some((t) => ease(spring, t) > 1));
  assert.equal(ease(spring, 2), 1);
});

test('Blueprint is linear: 150 ms open, 120 ms close, and its content scans in', () => {
  const m = islandMotion('linear');
  assert.deepEqual([m.open.ms, m.close.ms, m.swap.kind], [150, 120, 'scan']);
});

test('every motion on the theme menu has an island motion, and no token means none', () => {
  for (const motion of ['spring', 'snappy', 'ease', 'typewriter', 'linear']) assert.ok(islandMotion(motion), motion);
  assert.equal(islandMotion(undefined), null);
});

test('the one-line modes close; the cards open', () => {
  assert.deepEqual(['rest', 'playing', 'recording', 'toast'].map(isCompact), [true, true, true, true]);
  assert.deepEqual(['notification', 'question', 'calendar', 'osd'].map(isCompact), [false, false, false, false]);
});

test("an agent's lease sits just below a question and above the calendar and notifications (5G53CWPV)", () => {
  const lease = { who: 'claude', left: 60000 };
  assert.equal(pick({ question: { text: 'q', options: [] }, lease }), 'question');
  assert.equal(pick({ lease, calendar: { year: 2026, month: 9 }, notification: { app: 'a' }, osd: { kind: 'volume', value: 1 } }), 'lease');
  assert.equal(isCompact('lease'), true);
});

test('Mod+I during a lease opens its card, which only a question outranks', () => {
  const lease = { who: 'claude', left: 60000 };
  assert.equal(pick({ leaseCard: lease, lease }), 'leaseCard');
  assert.equal(pick({ question: { text: 'q', options: [] }, leaseCard: lease, lease }), 'question');
  assert.equal(isCompact('leaseCard'), false);
});

test('a send reads how many files go where and how far it got, on one line', () => {
  assert.equal(islandText('sending', { sending: { count: 2, to: 'nuc', pct: 48 } }, AT), 'Sending 2 files to nuc · 48%');
  assert.equal(islandText('sending', { sending: { count: 1, to: 'nu\nc', pct: 0 } }, AT), 'Sending 1 file to nu c · 0%');
  assert.equal(isCompact('sending'), true);
});
