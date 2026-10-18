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

// Array.prototype.flat and flatMap are ES2019, which QML's engine lacks, so a binding that calls one throws.
const qml = new URL('..', import.meta.url).pathname;

test('no shared module or QML file calls flat or flatMap', () => {
  const files = readdirSync(qml, { recursive: true }).filter((f) => (f.endsWith('.qml') || f.endsWith('.mjs')) && !f.endsWith('.test.mjs'));
  assert.deepEqual(
    files.filter((f) => /\.flat(Map)?\(/.test(readFileSync(qml + f, 'utf8'))),
    [],
  );
});
