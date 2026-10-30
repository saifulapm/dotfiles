// tests/dev/run.sh from an agent session: the whole nested suite runs only when asked for by name.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';

const run = new URL('../dev/run.sh', import.meta.url).pathname;

test('an agent session is refused the whole nested suite, and told how to ask for it', () => {
  const r = spawnSync('bash', [run], { env: { ...process.env, CLAUDECODE: '1', DOTS_DEV_ALL: '' }, encoding: 'utf8', timeout: 5000 });
  assert.equal(r.status, 1);
  assert.equal(r.stdout, '');
  assert.match(r.stderr, /DOTS_DEV_ALL=1/);
});
