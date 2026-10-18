import { test } from 'node:test';
import assert from 'node:assert/strict';
import { TIMES, validTimes } from './idle.mjs';

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
