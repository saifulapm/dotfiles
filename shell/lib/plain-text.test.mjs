import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';

// Notification text, window titles and track names come from other programs, and a Text left on AutoText renders their tags as rich text.
const shell = new URL('..', import.meta.url).pathname;

// The body of each `Text {` block, matched by its braces.
function textBlocks(src) {
  const blocks = [];
  for (const m of src.matchAll(/(^|[\s:])Text\s*\{/g)) {
    let depth = 0;
    for (let i = m.index + m[0].length - 1; i < src.length; i++) {
      if (src[i] === '{') depth++;
      else if (src[i] === '}' && --depth === 0) {
        blocks.push({ at: src.slice(0, m.index).split('\n').length, body: src.slice(m.index, i) });
        break;
      }
    }
  }
  return blocks;
}

test('every Text in the shell sets textFormat: Text.PlainText', () => {
  const found = [];
  for (const f of readdirSync(shell).filter((f) => f.endsWith('.qml'))) {
    for (const b of textBlocks(readFileSync(shell + f, 'utf8'))) {
      if (!/textFormat:\s*Text\.PlainText/.test(b.body)) found.push(`${f}:${b.at}`);
    }
  }
  assert.deepEqual(found, []);
});
