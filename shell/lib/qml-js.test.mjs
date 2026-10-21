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

// String trimStart and trimEnd are ES2019 too; the calculator once met trimStart in QML.
test('no shared module or QML file calls trimStart or trimEnd', () => {
  const files = readdirSync(qml, { recursive: true }).filter((f) => (f.endsWith('.qml') || f.endsWith('.mjs')) && !f.endsWith('.test.mjs'));
  assert.deepEqual(
    files.filter((f) => /\.trim(Start|End)\(/.test(readFileSync(qml + f, 'utf8'))),
    [],
  );
});

// A catch with no binding is ES2019 as well; QML refuses the whole module as a syntax error, and the shell with it.
test('no shared module or QML file catches without a binding', () => {
  const files = readdirSync(qml, { recursive: true }).filter((f) => (f.endsWith('.qml') || f.endsWith('.mjs')) && !f.endsWith('.test.mjs'));
  assert.deepEqual(
    files.filter((f) => /\bcatch\s*\{/.test(readFileSync(qml + f, 'utf8'))),
    [],
  );
});

// QML refuses a method named after a JavaScript global, such as escape, with "Illegal method name", and the file's type goes unavailable with it.
test('no QML file names a method after a JavaScript global', () => {
  const files = readdirSync(qml, { recursive: true }).filter((f) => f.endsWith('.qml'));
  const globals = 'escape|unescape|eval|isNaN|isFinite|parseInt|parseFloat|encodeURI|decodeURI|encodeURIComponent|decodeURIComponent';
  const named = new RegExp(`^\\s*function (${globals})\\s*\\(`, 'm');
  assert.deepEqual(
    files.filter((f) => named.test(readFileSync(qml + f, 'utf8'))),
    [],
  );
});
