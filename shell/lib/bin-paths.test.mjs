import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readdirSync, readFileSync } from 'node:fs';

// bin/dots-dev-shell runs the nested shell without bin/ on PATH, so a script named bare starts nothing there (m84, 0J1M54PS): the shell and its Apps start each bin/ script by Quickshell.shellDir + "/../bin/<name>".
const shell = new URL('../', import.meta.url).pathname;
const bin = new URL('../../bin/', import.meta.url).pathname;

const qmlFiles = (dir) => readdirSync(dir, { withFileTypes: true }).flatMap((e) => (e.isDirectory() ? qmlFiles(`${dir}${e.name}/`) : e.name.endsWith('.qml') ? [`${dir}${e.name}`] : []));

test('no QML names a bin/ script bare', () => {
  const found = [];
  for (const f of qmlFiles(shell)) {
    readFileSync(f, 'utf8')
      .split('\n')
      .forEach((line, i) => {
        for (const m of line.matchAll(/"(dots-[a-z0-9-]+)"/g)) if (existsSync(bin + m[1])) found.push(`${f.slice(shell.length)}:${i + 1} ${m[1]}`);
      });
  }
  assert.deepEqual(found, []);
});
