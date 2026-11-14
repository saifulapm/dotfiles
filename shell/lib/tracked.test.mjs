import { test } from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';

const root = new URL('../..', import.meta.url).pathname;

// The repo has no ignore rule for Python bytecode, and a `git add -A bin` once committed bin/__pycache__.
test('no tracked path is Python bytecode', () => {
  const tracked = execFileSync('git', ['ls-files', '-z'], { cwd: root, encoding: 'utf8' }).split('\0');
  assert.deepEqual(tracked.filter((f) => /(^|\/)__pycache__\/|\.py[co]$/.test(f)), []);
});
