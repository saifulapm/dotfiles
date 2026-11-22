import { test } from 'node:test';
import assert from 'node:assert/strict';
import { pad2, dateText, clockText, msToNextMinute, batteryText } from './margins.mjs';

const AT = new Date(2026, 9, 18, 14, 32, 10, 500);

test('pads a workspace index to two digits', () => {
  assert.equal(pad2(1), '01');
  assert.equal(pad2(12), '12');
});

test('the date reads as weekday, day and month', () => {
  assert.equal(dateText(AT), 'Sun 18 Oct');
  assert.equal(dateText(new Date(2026, 10, 2)), 'Mon 2 Nov');
});

test('the clock reads 24 hour HH:MM', () => {
  assert.equal(clockText(AT), '14:32');
  assert.equal(clockText(new Date(2026, 9, 19, 0, 5)), '00:05');
});

test('the tick waits until the next minute boundary', () => {
  assert.equal(msToNextMinute(AT), 49500);
  assert.equal(msToNextMinute(new Date(2026, 9, 18, 23, 59, 0, 0)), 60000);
});

test('the battery reads its percentage, and says when it is charging', () => {
  assert.equal(batteryText(0.82, false), '82%');
  assert.equal(batteryText(0.82, true), '82% charging');
});
