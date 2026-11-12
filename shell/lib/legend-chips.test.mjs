import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';

// Twelve surfaces each drew their own copy of the legend's chip, so one style change touched 26 files (2026-11-05); every surface now draws a key and its word with shell/KeyPair.qml.
const shell = new URL('../', import.meta.url).pathname;

const qmlFiles = (dir) => readdirSync(dir, { withFileTypes: true }).flatMap((e) => (e.isDirectory() ? qmlFiles(`${dir}${e.name}/`) : e.name.endsWith('.qml') ? [`${dir}${e.name}`] : []));

test('only KeyPair.qml draws a legend chip from the look', () => {
  const found = [];
  for (const f of qmlFiles(shell)) {
    if (f === `${shell}KeyPair.qml`) continue;
    readFileSync(f, 'utf8')
      .split('\n')
      .forEach((line, i) => {
        if (/\bchip\.(fill|key)\b/.test(line)) found.push(`${f.slice(shell.length)}:${i + 1}`);
      });
  }
  assert.deepEqual(found, []);
});
