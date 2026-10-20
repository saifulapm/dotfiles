import { test } from 'node:test';
import assert from 'node:assert/strict';
import { lowBattery } from './battery.mjs';

// Nothing warned before the battery ran out, and Asahi does not suspend, so the MacBook just went dark.
test('the battery warns once at 10% or less while discharging', () => {
  assert.deepEqual(lowBattery(true, 0.11, true), { warn: false, armed: true });
  assert.deepEqual(lowBattery(true, 0.1, true), { warn: true, armed: false });
  assert.deepEqual(lowBattery(false, 0.08, true), { warn: false, armed: false });
});

test('a battery hovering at 10% does not warn again until it stops discharging or passes 15%', () => {
  assert.deepEqual(lowBattery(false, 0.12, true), { warn: false, armed: false });
  assert.deepEqual(lowBattery(false, 0.16, true), { warn: false, armed: true });
  assert.deepEqual(lowBattery(false, 0.05, false), { warn: false, armed: true });
  assert.deepEqual(lowBattery(true, 0.05, false), { warn: false, armed: true });
});
