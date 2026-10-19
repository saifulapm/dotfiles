import { test } from 'node:test';
import assert from 'node:assert/strict';
import { verdict } from './soak.mjs';

// Minutes 0 to 30 at 150 MiB, with minute 30 moved by lastExtraMiB.
const csv = (lastExtraMiB) => {
  const rows = Array.from({ length: 31 }, (_, m) => `${m},${153600 + (m === 30 ? lastExtraMiB * 1024 : 0)}`);
  return ['minute,rss_kib', ...rows, ''].join('\n');
};

test('minute 30 4 MiB above minute 5 reads ok', () => {
  const v = verdict(csv(4));
  assert.equal(v.driftMiB, 4);
  assert.equal(v.ok, true);
  assert.equal(v.line, 'rss drift     4 MiB   ≤ 5 MiB    ok');
});

test('minute 30 6 MiB above minute 5 reads FAIL', () => {
  const v = verdict(csv(6));
  assert.equal(v.ok, false);
  assert.equal(v.line, 'rss drift     6 MiB   ≤ 5 MiB    FAIL');
});

test('exactly 5 MiB passes', () => {
  assert.equal(verdict(csv(5)).ok, true);
});

test('a CSV with no minute 5 row is refused', () => {
  assert.throws(() => verdict('minute,rss_kib\n0,1\n1,2\n'), /minute 5/);
});

test('minute 30 6 MiB below minute 5 is not within 5 MiB either', () => {
  const v = verdict(csv(-6));
  assert.equal(v.ok, false);
  assert.equal(v.line, 'rss drift     -6 MiB  ≤ 5 MiB    FAIL');
});
