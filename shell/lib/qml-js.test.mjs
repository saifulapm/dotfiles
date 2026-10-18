import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';

// QML's JavaScript engine cannot parse object spread, and the shell imports these modules.
const dir = new URL('.', import.meta.url).pathname;

test('no shared module uses object spread', () => {
  const found = readdirSync(dir)
    .filter((f) => f.endsWith('.mjs') && !f.endsWith('.test.mjs'))
    .filter((f) => /\{\s*\.\.\./.test(readFileSync(dir + f, 'utf8')));
  assert.deepEqual(found, []);
});
