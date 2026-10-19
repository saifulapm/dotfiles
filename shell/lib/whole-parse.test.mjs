import { test } from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

// bash reads a script as it runs, so an edit or a git pull mid-run shifts its offset; a script must parse whole before its first command and exit before bash reads on.
const root = new URL('../..', import.meta.url).pathname;
const files = execFileSync('git', ['ls-files', '--cached', '--others', '--exclude-standard'], { cwd: root, encoding: 'utf8' })
  .split('\n')
  .filter((f) => /^(bin|tests)\//.test(f));
const isPreamble = (line) => /^(#|set |shopt )/.test(line) || line.trim() === '';

// Safe shapes: the last line is `main "$@"; exit`, or one `{ ... }` group that ends on an exit line, after only a preamble.
const isWhole = (lines) => {
  const body = lines.filter((l) => l.trim() !== '');
  if (body[body.length - 1] === 'main "$@"; exit') return true;
  const open = lines.indexOf('{');
  if (open < 0 || body[body.length - 1] !== '}') return false;
  if (!lines.slice(0, open).every(isPreamble)) return false;
  return /^exit/.test(body[body.length - 2]) && body[body.length - 2] !== '{';
};

test('every bash script under bin/ and tests/ parses whole before it runs', () => {
  const found = [];
  for (const f of files) {
    const lines = readFileSync(join(root, f), 'utf8').split('\n');
    if (!/^#!.*\bbash\b/.test(lines[0])) continue;
    if (!isWhole(lines)) found.push(f);
  }
  assert.deepEqual(found, []);
});
