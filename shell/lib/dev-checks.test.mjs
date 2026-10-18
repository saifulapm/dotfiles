import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';

// A redirect on a check line silences the check's own ok or FAIL line, so the run hides the result.
const dir = new URL('../../tests/dev/', import.meta.url).pathname;

test('no check line in tests/dev redirects its output', () => {
  const found = [];
  for (const f of readdirSync(dir).filter((f) => f.endsWith('.sh'))) {
    readFileSync(dir + f, 'utf8')
      .split('\n')
      .forEach((line, i) => {
        if (/^\s*check\s/.test(line) && /(>|>>)\s*\/dev\/null\s*$/.test(line) && !/'[^']*>\s*\/dev\/null\s*'\s*$/.test(line)) found.push(`${f}:${i + 1}`);
      });
  }
  assert.deepEqual(found, []);
});
