import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { chmodSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const src = new URL('../../bin/dots-gestures.c', import.meta.url).pathname;

// The watcher is built once and run on recorded pinches, with fake dots-call and niri that log their argv.
function rig(t) {
  const dir = mkdtempSync(join(tmpdir(), 'gestures-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const cc = spawnSync('gcc', ['-O2', '-Wall', '-Werror', '-o', join(dir, 'dots-gestures'), src, '-linput', '-ludev'], { encoding: 'utf8' });
  assert.equal(cc.status, 0, cc.stderr);
  assert.equal(cc.stderr, '');
  const log = join(dir, 'calls.log');
  for (const name of ['dots-call', 'niri']) {
    writeFileSync(join(dir, name), `#!/bin/sh\necho "${name} $*" >> "${log}"\n`);
    chmodSync(join(dir, name), 0o755);
  }
  return (lines) => {
    const f = join(dir, 'events');
    writeFileSync(f, lines.join('\n') + '\n');
    rmSync(log, { force: true });
    const r = spawnSync(join(dir, 'dots-gestures'), [f], { env: { ...process.env, PATH: `${dir}:${process.env.PATH}` }, encoding: 'utf8', timeout: 1500 });
    assert.equal(r.status, 0, r.stderr);
    try { return readFileSync(log, 'utf8').split('\n').filter(Boolean); } catch { return []; }
  };
}

// A recorded pinch: begin with its fingers, the scale libinput reports as the hand moves, and end with libinput's cancelled flag.
const pinch = (fingers, scales, cancelled = 0) => [`begin ${fingers}`, ...scales.map((s) => `update ${s}`), `end ${cancelled}`];

test('a four-finger pinch in opens the launcher', (t) => {
  assert.deepEqual(rig(t)(pinch(4, [0.9, 0.7, 0.55])), ['dots-call launcher toggle']);
});

test('a four-finger pinch out toggles the overview', (t) => {
  assert.deepEqual(rig(t)(pinch(4, [1.2, 1.5, 1.8])), ['niri msg action toggle-overview']);
});

// Two-finger pinches zoom in Chromium, imv and zathura, and three fingers are niri's swipes.
test('a pinch with fewer than four fingers is left to the apps', (t) => {
  const run = rig(t);
  assert.deepEqual(run(pinch(2, [0.5])), []);
  assert.deepEqual(run(pinch(3, [1.8])), []);
});

test('a pinch that barely changes, or that libinput cancels, does nothing', (t) => {
  const run = rig(t);
  assert.deepEqual(run(pinch(4, [0.95, 1.05, 0.9])), []);
  assert.deepEqual(run(pinch(4, [0.5], 1)), []);
});

test('each pinch acts once, at its end', (t) => {
  assert.deepEqual(rig(t)([...pinch(4, [0.6, 0.5]), ...pinch(4, [1.6])]), ['dots-call launcher toggle', 'niri msg action toggle-overview']);
});
