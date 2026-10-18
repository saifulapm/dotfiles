import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { chmodSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const src = new URL('../../bin/dots-dshift.c', import.meta.url).pathname;
const [EV_SYN, EV_KEY, EV_REL] = [0, 1, 2];
const [KEY_A, LSHIFT, RSHIFT, BTN_LEFT, REL_WHEEL] = [30, 42, 54, 0x110, 8];

// One struct input_event as aarch64 lays it out: two 64-bit timeval longs, u16 type, u16 code, s32 value.
function ev(ms, type, code, value) {
  const b = Buffer.alloc(24);
  b.writeBigInt64LE(BigInt(Math.floor(ms / 1000)), 0);
  b.writeBigInt64LE(BigInt((ms % 1000) * 1000), 8);
  b.writeUInt16LE(type, 16);
  b.writeUInt16LE(code, 18);
  b.writeInt32LE(value, 20);
  return b;
}
const key = (ms, code, value) => [ev(ms, EV_KEY, code, value), ev(ms, EV_SYN, 0, 0)];
const tap = (ms, code = LSHIFT) => [...key(ms, code, 1), ...key(ms + 20, code, 0)];
const file = (...evs) => Buffer.concat(evs.flat());

// The watcher is built once and run on recorded files, with a fake qs that logs its argv.
function rig(t) {
  const dir = mkdtempSync(join(tmpdir(), 'dshift-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const cc = spawnSync('gcc', ['-O2', '-Wall', '-Werror', '-o', join(dir, 'dots-dshift'), src], { encoding: 'utf8' });
  assert.equal(cc.status, 0, cc.stderr);
  assert.equal(cc.stderr, '');
  const log = join(dir, 'qs.log');
  writeFileSync(join(dir, 'qs'), `#!/bin/sh\necho "$*" >> "${log}"\n`);
  chmodSync(join(dir, 'qs'), 0o755);
  return (events, args = []) => {
    const f = join(dir, 'events');
    writeFileSync(f, events);
    rmSync(log, { force: true });
    const r = spawnSync(join(dir, 'dots-dshift'), [...args, f], {
      env: { ...process.env, PATH: `${dir}:${process.env.PATH}` }, encoding: 'utf8', timeout: 1500,
    });
    assert.equal(r.status, 0, r.stderr);
    try { return readFileSync(log, 'utf8').split('\n').filter(Boolean); } catch { return []; }
  };
}

test('two clean Shift taps 150 ms apart run qs ipc notes capture, with the id when given', (t) => {
  const run = rig(t);
  const two = file(tap(1000), tap(1150));
  assert.deepEqual(run(two, ['-i', 'nested-1']), ['ipc -i nested-1 call notes capture']);
  assert.deepEqual(run(two), ['ipc call notes capture']);
  assert.deepEqual(run(file(tap(1000, LSHIFT), tap(1150, RSHIFT))), ['ipc call notes capture']);
});

test('taps 500 ms apart do nothing', (t) => {
  const run = rig(t);
  assert.deepEqual(run(file(tap(1000), tap(1500))), []);
});

test('another key, a mouse button or a wheel turn between taps breaks the pair', (t) => {
  const run = rig(t);
  const chord = [...key(1000, LSHIFT, 1), ...key(1010, KEY_A, 1), ...key(1020, KEY_A, 0), ...key(1030, LSHIFT, 0)];
  assert.deepEqual(run(file(chord, tap(1150))), []);
  assert.deepEqual(run(file(tap(1000), key(1100, BTN_LEFT, 1), tap(1150))), []);
  assert.deepEqual(run(file(tap(1000), [ev(1100, EV_REL, REL_WHEEL, 1)], tap(1150))), []);
});

test('autorepeat is ignored and a fired pair resets', (t) => {
  const run = rig(t);
  const held = [...key(1000, LSHIFT, 1), ...key(1010, LSHIFT, 2), ...key(1020, LSHIFT, 0)];
  assert.deepEqual(run(file(held, tap(1150))), ['ipc call notes capture']);
  assert.equal(run(file(tap(1000), tap(1150), tap(1300), tap(1450))).length, 2);
});
