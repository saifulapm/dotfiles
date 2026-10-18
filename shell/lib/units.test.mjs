import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

// just dev runs the shell as a transient unit, so its settings must match the real unit's.
const root = new URL('../..', import.meta.url).pathname;
const unit = readFileSync(root + 'home/dot_config/systemd/user/dots-shell.service', 'utf8');
const dev = readFileSync(root + 'bin/dots-dev-shell', 'utf8');

const unitProps = (key) => [...unit.matchAll(new RegExp(`^${key}=(.*)$`, 'gm'))].map((m) => m[1]);

test('the real unit restarts after 500 ms and never gives up', () => {
  assert.deepEqual(unitProps('Restart'), ['always']);
  assert.deepEqual(unitProps('RestartSec'), ['500ms']);
  assert.deepEqual(unitProps('StartLimitIntervalSec'), ['0']);
});

test('the dev unit restarts like the real one', () => {
  for (const p of ['Restart=always', 'RestartSec=500ms', 'StartLimitIntervalSec=0']) assert.match(dev, new RegExp(`-p ${p}\\b`));
});

test('the dev unit sets the same environment as the real one', () => {
  const real = unitProps('Environment').sort();
  const devEnv = [...dev.matchAll(/-E (\w+=\S*)/g)].map((m) => m[1]).sort();
  assert.deepEqual(devEnv, real);
  assert.ok(real.includes('QSG_RENDER_LOOP=basic'));
});
