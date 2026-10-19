import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';
import { checked } from '../../tests/sync/lib.mjs';

// This machine's rclone config reaches the real Dropbox, so tests/sync may start a process only through lib.mjs, which builds a scratch env.
const dir = new URL('../../tests/sync/', import.meta.url).pathname;
const SPAWN = /\b(spawn|spawnSync|exec|execSync|execFile|execFileSync|fork)\(/g;

test('no sync test starts a process except through the scratch env helper', () => {
  const tests = readdirSync(dir).filter((f) => f.endsWith('.test.mjs'));
  assert.notDeepEqual(tests, []);
  assert.deepEqual(tests.filter((f) => /child_process|\$`|\bspawn|\bexec/.test(readFileSync(dir + f, 'utf8'))), []);
  const lib = readFileSync(dir + 'lib.mjs', 'utf8');
  const calls = lib.match(SPAWN) ?? [];
  assert.equal(calls.length, 1);
  assert.equal((lib.match(/\{ env: checked\([a-z.]+\) \}\)/g) ?? []).length, calls.length);
});

test('the helper refuses a HOME outside the temp dir', () => {
  const env = { HOME: '/home/saiful', XDG_CONFIG_HOME: '/tmp', XDG_DATA_HOME: '/tmp', XDG_STATE_HOME: '/tmp', XDG_RUNTIME_DIR: '/tmp', RCLONE_CONFIG: '/tmp', DOTS_MACHINE: 'a' };
  assert.throws(() => checked(env), /refusing HOME=\/home\/saiful/);
});
