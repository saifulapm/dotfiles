import { test } from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

// m5: a rebase left a diff3 base block in bin/dots-dev-shell, and only an unrelated test noticed; untracked files count, so a file is checked before its commit.
const root = new URL('../..', import.meta.url).pathname;
const files = execFileSync('git', ['ls-files', '--cached', '--others', '--exclude-standard'], { cwd: root, encoding: 'utf8' })
  .split('\n')
  .filter((f) => f && !f.startsWith('.claude/'));
const marker = new RegExp(`^(${['<', '|', '>'].map((c) => '\\' + c + '{7}').join('|')})( |$)`);

test('no file keeps a merge conflict marker', () => {
  const found = [];
  for (const f of files) {
    let text;
    try {
      text = readFileSync(join(root, f), 'utf8');
    } catch {
      continue;
    }
    text.split('\n').forEach((line, i) => {
      if (marker.test(line)) found.push(`${f}:${i + 1}`);
    });
  }
  assert.deepEqual(found, []);
});
