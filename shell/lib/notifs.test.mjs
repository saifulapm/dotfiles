import { test } from 'node:test';
import assert from 'node:assert/strict';
import { addEntry, parseStore, storeText, LIMIT } from './notifs.mjs';

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
