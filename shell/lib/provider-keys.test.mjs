import { test } from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';

// Saiful's keys live in pass, so a key-shaped string in the repo is a stand-in, and a scanner cannot tell a stand-in from a leak.
const root = new URL('../..', import.meta.url).pathname;
const files = execFileSync('git', ['ls-files', '--cached', '--others', '--exclude-standard'], { cwd: root, encoding: 'utf8' }).split('\n').filter(Boolean);
const OPENROUTER = /sk-or-v1-[0-9a-f]{64}/;

test('no file in the repo holds a string in the shape of an OpenRouter key', () => {
  const hits = files.filter((f) => {
    try {
      return OPENROUTER.test(readFileSync(root + f, 'latin1'));
    } catch {
      return false;
    }
  });
  assert.deepEqual(hits, []);
});
