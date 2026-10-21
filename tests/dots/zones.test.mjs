// dots-zones run for real, asked "as of" fixed instants around the 2026 clock changes.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';

const bin = new URL('../../bin/dots-zones', import.meta.url).pathname;
const run = (epoch) => JSON.parse(execFileSync(bin, [String(epoch)], { env: { ...process.env, TZ: 'Asia/Dhaka' } }).toString());
const offset = (out, id) => out.zones.find((z) => z.id === id).offset;
const at = (iso) => Date.parse(iso) / 1000;

test('before London changes: BST, and the next change is London on 2026-10-25', () => {
  const out = run(at('2026-10-22T09:12:00Z'));
  assert.equal(out.home, 'Asia/Dhaka');
  assert.deepEqual(out.zones.map((z) => [z.id, z.city, z.offset]), [
    ['Asia/Dhaka', 'Dhaka', 21600], ['UTC', 'UTC', 0],
    ['Europe/London', 'London', 3600], ['America/New_York', 'New York', -14400]]);
  assert.equal(out.next, at('2026-10-25T01:00:00Z'));
});

test('after London changes: London is +0 and the next change is New York on 2026-11-01', () => {
  const out = run(at('2026-10-25T01:00:00Z'));
  assert.equal(offset(out, 'Europe/London'), 0);
  assert.equal(offset(out, 'America/New_York'), -14400);
  assert.equal(out.next, at('2026-11-01T06:00:00Z'));
});

test('after New York changes too: -5h, and the next change is the March ones', () => {
  const out = run(at('2026-11-02T00:00:00Z'));
  assert.equal(offset(out, 'America/New_York'), -18000);
  assert.equal(out.next, at('2027-03-14T07:00:00Z'));
});
