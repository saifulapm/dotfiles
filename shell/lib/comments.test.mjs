import { test } from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

// The repo keeps comments to one line, so two comment lines in a row are refused.
const root = new URL('../..', import.meta.url).pathname;
const files = execFileSync('git', ['ls-files'], { cwd: root, encoding: 'utf8' })
  .split('\n')
  .filter((f) => /\.(qml|mjs|sh|kdl|tmpl|service|toml)$|^bin\//.test(f));
// In C a leading # is the preprocessor, not a comment.
const isComment = (f, line) => (f.endsWith('.c') ? /^\s*\/\//.test(line) : /^\s*(\/\/|#)/.test(line) && !/^#!/.test(line) && !/^\s*# shellcheck /.test(line));

test('no file has two comment lines in a row', () => {
  const found = [];
  for (const f of files) {
    const lines = readFileSync(join(root, f), 'utf8').split('\n');
    lines.forEach((line, i) => {
      if (i > 0 && isComment(f, line) && isComment(f, lines[i - 1])) found.push(`${f}:${i + 1}`);
    });
  }
  assert.deepEqual(found, []);
});
