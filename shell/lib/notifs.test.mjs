import { test } from 'node:test';
import assert from 'node:assert/strict';
import { addEntry, parseStore, storeText, LIMIT, visible, group, clampSelected } from './notifs.mjs';

const entry = (n, app = 'notify-send') => ({ key: `k${n}`, app, summary: `n ${n}`, body: '', critical: false, time: 1000 + n, actions: [] });

test('the newest entry goes first', () => {
  const h = addEntry(addEntry([], entry(1)), entry(2));
  assert.deepEqual(h.map((e) => e.summary), ['n 2', 'n 1']);
});

test('the history keeps 200 entries and drops the oldest', () => {
  assert.equal(LIMIT, 200);
  let h = [];
  for (let i = 1; i <= 201; i++) h = addEntry(h, entry(i));
  assert.equal(h.length, 200);
  assert.equal(h[0].summary, 'n 201');
  assert.equal(h.at(-1).summary, 'n 2');
});

test('the store round-trips the history and Do Not Disturb', () => {
  const h = [entry(2), entry(1)];
  assert.deepEqual(parseStore(storeText({ dnd: true, history: h })), { dnd: true, history: h });
});

test('a missing, broken or foreign store reads as empty', () => {
  for (const text of ['', '{', '[]', '{"history":3}', 'null']) assert.deepEqual(parseStore(text), { dnd: false, history: [] });
});

test('a stored entry missing its fields is dropped, and a long store is cut to 200', () => {
  const many = Array.from({ length: 250 }, (_, i) => entry(250 - i));
  const s = parseStore(JSON.stringify({ dnd: 'yes', history: [{ app: 1 }, ...many] }));
  assert.equal(s.dnd, false);
  assert.equal(s.history.length, 200);
  assert.equal(s.history[0].summary, 'n 250');
});

const from = (app, summary, time, body = '') => ({ key: `${app}-${time}`, app, summary, body, critical: false, time, actions: [] });
const shape = (groups) => groups.map((g) => [g.app, g.entries.map((e) => e.summary)]);

test('each app gets one group, groups by their newest entry, entries newest first', () => {
  const history = [from('chat', 'c3', 50), from('mail', 'm2', 40), from('chat', 'c2', 30), from('mail', 'm1', 20), from('chat', 'c1', 10)];
  assert.deepEqual(shape(group(history)), [
    ['chat', ['c3', 'c2', 'c1']],
    ['mail', ['m2', 'm1']],
  ]);
  assert.deepEqual(shape(group([from('mail', 'm1', 20), from('chat', 'c1', 30)])), [
    ['chat', ['c1']],
    ['mail', ['m1']],
  ]);
});

test('search matches app, summary or body, ignoring case', () => {
  const history = [from('Chat', 'lunch?', 30), from('mail', 'Invoice', 20, 'due Friday'), from('mail', 'hello', 10)];
  const found = (q) => visible(history, q).map((e) => e.summary);
  assert.deepEqual(found(''), ['lunch?', 'Invoice', 'hello']);
  assert.deepEqual(found('CHAT'), ['lunch?']);
  assert.deepEqual(found('invoice'), ['Invoice']);
  assert.deepEqual(found('friday'), ['Invoice']);
  assert.deepEqual(found('nothing'), []);
});

test('the selection stays in range after a removal', () => {
  assert.equal(clampSelected(2, 2), 1);
  assert.equal(clampSelected(1, 3), 1);
  assert.equal(clampSelected(0, 0), 0);
  assert.equal(clampSelected(-1, 3), 0);
});
