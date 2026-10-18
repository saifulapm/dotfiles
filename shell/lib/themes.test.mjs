import { test } from 'node:test';
import assert from 'node:assert/strict';
import { step, summary } from './themes.mjs';

const names = ['paper', 'artboard', 'blueprint'];

test('step moves the cursor by one name and stops at the ends', () => {
  assert.equal(step(names, 'paper', 1), 'artboard');
  assert.equal(step(names, 'blueprint', -1), 'artboard');
  assert.equal(step(names, 'blueprint', 1), 'blueprint');
  assert.equal(step(names, 'paper', -1), 'paper');
});

test('summary names the mode, frame and shadow', () => {
  assert.equal(summary({ mode: 'light', primitive: { frame: 'ink', shadow: 'hard-offset' } }), 'light · ink · hard shadow');
  assert.equal(summary({ mode: 'dark', primitive: { frame: 'glow', shadow: 'none' } }), 'dark · glow · no shadow');
  assert.equal(summary({ mode: 'light', primitive: { frame: 'none', shadow: 'soft' } }), 'light · no frame · soft shadow');
});
