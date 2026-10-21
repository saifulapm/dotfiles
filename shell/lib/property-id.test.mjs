import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';

// A property named after an id in its own file shadows that id for every binding in scope, so `card.text` read the property, not the item (m21).
const shell = new URL('..', import.meta.url).pathname;

export function clashes(text) {
  const ids = new Set([...text.matchAll(/^\s*id:\s*(\w+)/gm)].map((m) => m[1]));
  const props = [...text.matchAll(/^\s*(?:(?:readonly|required|default)\s+)*property\s+[\w.<>]+\s+(\w+)/gm)].map((m) => m[1]);
  return props.filter((p) => ids.has(p));
}

test('a property sharing a name with an id in its file is caught', () => {
  assert.deepEqual(clashes('Item {\n    property var card\n    Rectangle {\n        id: card\n    }\n}\n'), ['card']);
  assert.deepEqual(clashes('Item {\n    readonly property list<var> rows: []\n    id: rows\n}\n'), ['rows']);
  assert.deepEqual(clashes('Item {\n    property var cards\n    Rectangle { id: card }\n}\n'), []);
});

test('no .qml under shell/ declares a property named after an id in the same file', () => {
  const found = readdirSync(shell, { recursive: true })
    .filter((f) => f.endsWith('.qml'))
    .flatMap((f) => clashes(readFileSync(join(shell, f), 'utf8')).map((p) => `${f}: ${p}`));
  assert.deepEqual(found, []);
});
