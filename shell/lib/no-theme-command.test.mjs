import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync, statSync } from 'node:fs';

// `dots theme` exits 1 since dots colorscheme replaced it, so a caller left on it fails at run time; this finds one before it runs.
const root = new URL('../../', import.meta.url).pathname;
const self = 'shell/lib/no-theme-command.test.mjs';
const call = /dots theme\s|dots"\s+theme\b|\/dots\s+theme\b|dots['"]?\s*,\s*\[\s*['"]theme['"]/;
// dots-colorscheme.test.mjs runs the old command on purpose, to check that it is refused.
const allowed = { 'shell/lib/dots-colorscheme.test.mjs': /spawnSync\(dots, \['theme'|doesNotMatch\(usage, \/dots theme\// };

function files(dir) {
  return readdirSync(root + dir, { recursive: true })
    .map((f) => `${dir}/${f}`)
    .filter((f) => !/(^|\/)(node_modules|\.git)(\/|$)/.test(f) && f !== self && statSync(root + f).isFile());
}

// A comment that names the old command misleads as much as a call, so comments are read too.
test('nothing in bin, home, shell or tests calls or names the theme command', () => {
  const found = [];
  for (const f of ['bin', 'home', 'shell', 'tests'].flatMap(files)) {
    readFileSync(root + f, 'utf8')
      .split('\n')
      .forEach((line, i) => {
        if (!call.test(line)) return;
        if (allowed[f] && allowed[f].test(line)) return;
        found.push(`${f}:${i + 1}`);
      });
  }
  assert.deepEqual(found, []);
});
