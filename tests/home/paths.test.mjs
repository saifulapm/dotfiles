// Projects and this repo moved from ~/Sites to ~/Codes (S2PMMBJA, F1GR9QGW), so nothing in the repo may name the old folder.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { lstatSync, readFileSync } from 'node:fs';
import { join } from 'node:path';

const root = new URL('../..', import.meta.url).pathname;
const self = 'tests/home/paths.test.mjs';

test('no file names a path under ~/Sites', () => {
  const files = execFileSync('git', ['ls-files', '--cached', '--others', '--exclude-standard'], { cwd: root, encoding: 'utf8' })
    .split('\n')
    .filter((f) => f && f !== self);
  const found = [];
  // A link such as shell/bin names its target, which git checks as the link itself.
  for (const f of files.filter((f) => !lstatSync(join(root, f)).isSymbolicLink())) {
    readFileSync(join(root, f), 'utf8').split('\n').forEach((line, i) => {
      if (/\bSites\b/.test(line)) found.push(`${f}:${i + 1}`);
    });
  }
  assert.deepEqual(found, []);
});
