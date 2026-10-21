import { test } from 'node:test';
import assert from 'node:assert/strict';
import { MAX_MS, minutesOf, leaseEnd, holder, unlockLine } from './lease.mjs';

const MIN = 60000;

test('a lease runs 15 minutes unless told a positive number', () => {
  assert.equal(minutesOf('15'), 15);
  assert.equal(minutesOf('1'), 1);
  assert.equal(minutesOf('0.5'), 0.5);
  for (const bad of ['', 'ten', '0', '-3', 'NaN', 'Infinity', undefined]) assert.equal(minutesOf(bad), 15, String(bad));
});

test('no lease ends later than 2 hours after its unlock (RJA7QN1K)', () => {
  assert.equal(MAX_MS, 120 * MIN);
  const at = 1_000_000;
  assert.equal(leaseEnd(at, at, 1), at + MIN);
  assert.equal(leaseEnd(at, at, 200), at + 120 * MIN);
  assert.equal(leaseEnd(at, at + 110 * MIN, 15), at + 120 * MIN);
  assert.equal(leaseEnd(at, at + 10 * MIN, 15), at + 25 * MIN);
});

test('the holder is one line any sender spells, and never empty', () => {
  assert.equal(holder('claude'), 'claude');
  assert.equal(holder('cl\naude\t x'), 'cl aude x');
  assert.equal(holder('‮edualc'), 'edualc');
  assert.equal(holder(''), 'agent');
  assert.equal(holder(' \n '), 'agent');
  assert.equal(holder('x'.repeat(200)), 'x'.repeat(200));
  // Control characters draw as tofu, show as a blob in the journal and replay on a terminal; U+0085 splits a line, and the bidi marks reorder.
  assert.equal(holder('AAA\x1b\x07\x08\x7fBBB\u200fCCC\u061cDDD'), 'AAA BBBCCCDDD');
  assert.equal(holder('AAA\u0085BBB\u200eC'), 'AAA BBBC');
  assert.equal(holder('\x00\x1b'), 'agent');
});

test('the journal line names who and for how long (MBFQCTFH)', () => {
  assert.equal(unlockLine('claude', 1), 'lock: agent unlock by claude for 1 min');
});
