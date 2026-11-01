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

// The island's question draws Q.linkify's html, which escapes the text before it adds links (questions.test.mjs), so that Text alone may be StyledText.
const STYLED = ['Island.qml:askText'];

test('every Text in the shell sets textFormat: Text.PlainText, but the escaped question links', () => {
  const found = [];
  for (const f of readdirSync(shell).filter((f) => f.endsWith('.qml'))) {
    for (const b of textBlocks(readFileSync(shell + f, 'utf8'))) {
      const id = (b.body.match(/\bid:\s*(\w+)/) || [])[1];
      if (STYLED.includes(`${f}:${id}`) && /textFormat:[^\n]*Text\.StyledText/.test(b.body)) continue;
      if (!/textFormat:\s*Text\.PlainText/.test(b.body)) found.push(`${f}:${b.at}`);
    }
  }
  assert.deepEqual(found, []);
});
