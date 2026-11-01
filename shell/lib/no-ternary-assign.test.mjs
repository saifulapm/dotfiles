import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';

// Quickshell's QML engine drops an assignment made inside a ternary's branch while node runs it, so a unit test passes on code that does nothing in the shell (m72's Playlist move).
const lib = new URL('.', import.meta.url).pathname;
// A branch after ? or : that opens with a parenthesised assignment: `? (a[k] = v)` or `: (seen[k] = true)`.
const BRANCH_ASSIGN = /[?:]\s*\(\s*[\w$.]+(?:\[[^\]]*\])*\s*[-+*/%|&]?=(?![=>])/;

test('the lint sees an assignment in either branch of a ternary, and not a comparison or an arrow', () => {
  assert.match('k === i ? it : (items[k] = next)', BRANCH_ASSIGN);
  assert.match('seen[e.key] ? false : (seen[e.key] = true)', BRANCH_ASSIGN);
  assert.match('ok ? (n += 1) : n', BRANCH_ASSIGN);
  assert.doesNotMatch('ok ? (a === b) : (c => c)', BRANCH_ASSIGN);
  assert.doesNotMatch('ok ? (x) : (y => y + 1)', BRANCH_ASSIGN);
});

test('no shell/lib module assigns inside a ternary branch', () => {
  const found = [];
  for (const f of readdirSync(lib)) {
    if (!f.endsWith('.mjs') || f.endsWith('.test.mjs')) continue;
    readFileSync(join(lib, f), 'utf8').split('\n').forEach((l, i) => {
      if (!l.trim().startsWith('//') && BRANCH_ASSIGN.test(l)) found.push(`${f}:${i + 1}: ${l.trim()}`);
    });
  }
  assert.deepEqual(found, [], 'move the assignment into a statement of its own');
});
