import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';

// A helper in the runner's list would run as a check and end every whole run red.
const dir = new URL('../../tests/dev/', import.meta.url).pathname;
const sourcesLib = (f) => /^source "\$\(dirname "\$0"\)\/lib\.sh"/m.test(readFileSync(dir + f, 'utf8'));
const sourcesLibVia = (f) => [...readFileSync(dir + f, 'utf8').matchAll(/^source "\$\(dirname "\$0"\)\/(lib-[\w-]+\.sh)/gm)].some((m) => sourcesLib(m[1]));

test('run.sh --list names only scripts that source lib.sh, directly or through a lib-*.sh', () => {
  const run = spawnSync('bash', [dir + 'run.sh', '--list'], { encoding: 'utf8', env: { ...process.env, CLAUDECODE: '1', DOTS_DEV_ALL: '' } });
  assert.equal(run.status, 0, run.stderr);
  const names = run.stdout.split('\n').filter(Boolean);
  assert.ok(names.length > 0, 'the list names checks');
  assert.deepEqual(names.filter((f) => !sourcesLib(f) && !sourcesLibVia(f)), []);
});
