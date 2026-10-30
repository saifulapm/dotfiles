import { test } from 'node:test';
import assert from 'node:assert/strict';
import { TIMES, validTimes, awakeMinutes, awakeEnd, nextAwake, awakeWord, awakeDetail } from './idle.mjs';

test('the idle steps dim at 4 min, lock at 5 and turn monitors off at 6', () => {
  assert.deepEqual(TIMES, [240, 300, 360]);
});

test('times must be whole seconds that rise step by step', () => {
  assert.ok(validTimes([4, 5, 6]));
  assert.ok(!validTimes([5, 4, 6]));
  assert.ok(!validTimes([0, 5, 6]));
  assert.ok(!validTimes([4, 5]));
  assert.ok(!validTimes([4.5, 5, 6]));
});

test('stay awake takes whole minutes up to a day, and anything else turns it off', () => {
  assert.equal(awakeMinutes('60'), 60);
  assert.equal(awakeMinutes(' 1440 '), 1440);
  for (const t of ['off', '0', '', '1441', '1.5', '-5', '60m', null]) assert.equal(awakeMinutes(t), 0, String(t));
});

test('stay awake ends that many minutes from now, and 0 minutes is off', () => {
  assert.equal(awakeEnd(1000, 2), 121000);
  assert.equal(awakeEnd(1000, 0), 0);
});

test("Control's row steps off, 30 min, 1 h, 2 h and back to off", () => {
  const now = 1_000_000;
  const at = nextAwake(now, 0);
  assert.equal(at, now + 30 * 60000);
  const hour = nextAwake(now, at);
  assert.equal(hour, now + 60 * 60000);
  const two = nextAwake(now, hour);
  assert.equal(two, now + 120 * 60000);
  assert.equal(nextAwake(now, two), 0);
  // A time already passed counts as off.
  assert.equal(nextAwake(now, now - 1), now + 30 * 60000);
  // 20 min left of a 30 min hold starts the 30 min again.
  assert.equal(nextAwake(now, now + 20 * 60000), now + 30 * 60000);
});

test('the margin reads awake and the end, Control until and the end, or off', () => {
  const until = new Date(2026, 9, 30, 14, 5).getTime();
  assert.equal(awakeWord(until), 'awake 14:05');
  assert.equal(awakeWord(0), '');
  assert.equal(awakeDetail(until), 'until 14:05');
  assert.equal(awakeDetail(0), 'off');
});
