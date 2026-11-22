import { test } from 'node:test';
import assert from 'node:assert/strict';
import { expiry, arrive, take, drop, count, pile } from './island-wait.mjs';

const note = (key, at, expires = null, entry = key) => ({ kind: 'notification', key, at, expires, entry });
const ask = (key, at, entry = key) => ({ kind: 'question', key, at, expires: null, entry });
const fill = (items) => items.reduce(arrive, []);

// The keys that take hands out one after another, until nothing is left to show.
function drain(queue, now) {
  const order = [];
  for (let t = take(queue, now); t.next; t = take(t.rest, now)) order.push(t.next.key);
  return order;
}

test('three notifications a, b, c come out a, b, c', () => {
  assert.deepEqual(drain(fill([note('a', 1), note('b', 2), note('c', 3)]), 0), ['a', 'b', 'c']);
});

test('questions come before notifications, each in arrival order', () => {
  const q = fill([note('n1', 1), ask('q1', 2), note('n2', 3), ask('q2', 4)]);
  assert.deepEqual(drain(q, 0), ['q1', 'q2', 'n1', 'n2']);
});

test('a notification whose time ran out is expired, one that never expires is next', () => {
  const t = take(fill([note('old', 1, 1000)]), 1000);
  assert.equal(t.next, null);
  assert.deepEqual(t.expired.map((i) => i.key), ['old']);
  assert.deepEqual(t.rest, []);
  const crit = take(fill([note('crit', 1, null)]), 1e12);
  assert.equal(crit.next.key, 'crit');
  assert.deepEqual(crit.expired, []);
});

test('a replaced notification counts once, keeps its place, arrival and expiry, and comes out with the new entry', () => {
  const q = fill([note('a', 1, 5000, 'first'), note('b', 2), note('a', 9, 8000, 'second')]);
  assert.equal(count(q), 2);
  assert.deepEqual(q.map((i) => [i.key, i.at, i.entry, i.expires]), [['a', 1, 'second', 5000], ['b', 2, 'b', null]]);
  assert.equal(take(q, 0).next.entry, 'second');
  assert.deepEqual(take(q, 6000).expired.map((i) => i.key), ['a']);
});

test('drop removes only the named key, and arrive, take and drop leave their input alone', () => {
  const q = fill([note('a', 1), ask('b', 2), note('c', 3, 10)]);
  const before = structuredClone(q);
  assert.deepEqual(drop(q, 'b').map((i) => i.key), ['a', 'c']);
  arrive(q, note('a', 5, null, 'x'));
  arrive(q, note('d', 6));
  take(q, 100);
  assert.deepEqual(q, before);
});

test('expiry adds the hold to the arrival, and a hold of 0 never expires', () => {
  assert.equal(expiry(1000, 5000), 6000);
  assert.equal(expiry(1000, 0), null);
});

test('the stack counts the shown notification, the criticals under it and those waiting, by app', () => {
  const e = (key, app) => ({ key, app });
  const q = (key, app) => ({ kind: 'notification', key, entry: e(key, app) });
  assert.deepEqual(pile(null, [e('a', 'Battery')], []), { count: 0, app: '', same: 0, others: 0 });
  assert.deepEqual(pile(e('c', 'Battery'), [e('b', 'Battery'), e('a', 'Battery')], []), { count: 3, app: 'Battery', same: 3, others: 0 });
  assert.deepEqual(pile(e('c', 'Battery'), [e('b', 'Battery')], [q('m', 'Mail'), { kind: 'question', key: 'q1' }, q('c', 'Battery')]), { count: 3, app: 'Battery', same: 2, others: 1 });
});
