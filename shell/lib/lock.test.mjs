import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';

// Only PAM may end the lock: an IPC unlock would let any local process skip the password.
const root = new URL('../..', import.meta.url).pathname;
const lock = readFileSync(root + 'shell/Lock.qml', 'utf8');

function ipcFunctions(src) {
  const at = src.search(/IpcHandler\s*\{/);
  assert.ok(at >= 0, 'Lock.qml has an IpcHandler');
  let depth = 0;
  for (let i = src.indexOf('{', at); i < src.length; i++) {
    if (src[i] === '{') depth++;
    else if (src[i] === '}' && --depth === 0) return [...src.slice(at, i).matchAll(/function\s+(\w+)\s*\(/g)].map((m) => m[1]);
  }
  assert.fail('the IpcHandler block never closes');
}

test('the lock IPC offers lock and state, never unlock', () => {
  assert.deepEqual(ipcFunctions(lock).sort(), ['lock', 'state']);
  assert.doesNotMatch(lock, /\.unlock\s*\(/);
});

const checker = (input) => spawnSync(root + 'dev/pam-test-password', { input }).status;

test('the dev PAM checker rejects an empty token', () => {
  assert.equal(checker(''), 1);
});

test('the dev PAM checker accepts only the test password', () => {
  assert.equal(checker('dots-test-pass'), 0);
  assert.equal(checker('dots-test-pas'), 1);
  assert.equal(checker('wrong'), 1);
});
