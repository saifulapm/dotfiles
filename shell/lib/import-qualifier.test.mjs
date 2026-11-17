import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';

// Two imports under one qualifier stop the whole file loading ("Script import qualifiers must be unique"), which no node test sees; m101's island-wait import as W, beside worldclock's W, took the island out of every nested check.
const shell = new URL('..', import.meta.url).pathname;

export function repeated(text) {
  const names = [...text.matchAll(/^import\s+\S+(?:\s+[\d.]+)?\s+as\s+(\w+)\s*$/gm)].map((m) => m[1]);
  return [...new Set(names.filter((n, i) => names.indexOf(n) !== i))];
}

test('a qualifier used by two imports in a file is caught', () => {
  assert.deepEqual(repeated('import "lib/a.mjs" as W\nimport "lib/b.mjs" as W\n'), ['W']);
  assert.deepEqual(repeated('import "lib/a.mjs" as W\nimport "lib/b.mjs" as Wq\nimport "." as Root\n'), []);
});

test('no .qml under shell/ imports two things under one qualifier', () => {
  const found = readdirSync(shell, { recursive: true })
    .filter((f) => f.endsWith('.qml'))
    .flatMap((f) => repeated(readFileSync(join(shell, f), 'utf8')).map((q) => `${f}: ${q}`));
  assert.deepEqual(found, []);
});
