import { test } from 'node:test';
import assert from 'node:assert/strict';
import { blocks, clean, sse } from './chat.mjs';

// Qt's XMLHttpRequest decodes the whole body so far on each readyState 3, so a chunk that ends inside a character reads as U+FFFD until the next one lands.
function decodedPrefixes(body, cuts) {
  const bytes = new TextEncoder().encode(body);
  return cuts.map((n) => new TextDecoder().decode(bytes.subarray(0, n)));
}

test('server-sent events split mid-line and mid-character come out whole, once each', () => {
  const body =
    'data: {"choices":[{"delta":{"content":"আমার "}}]}\n\n' +
    ': keep-alive\n\n' +
    'data: {"choices":[{"delta":{"content":"fish ✓"}}]}\n\n' +
    'data: [DONE]\n\n';
  const bytes = new TextEncoder().encode(body).length;
  // every cut point: mid-line, mid-character, between events
  const reader = sse();
  const got = [];
  let done = false;
  for (const text of decodedPrefixes(body, Array.from({ length: bytes }, (_, i) => i + 1))) {
    const r = reader.feed(text);
    got.push(...r.events);
    done = done || r.done;
  }
  assert.deepEqual(
    got.map((e) => e.choices[0].delta.content),
    ['আমার ', 'fish ✓'],
  );
  assert.equal(done, true);
});

test('an event whose data is not JSON is skipped, and the stream reads on', () => {
  const reader = sse();
  const r = reader.feed('data: {oops\n\ndata: {"a":1}\n\n');
  assert.deepEqual(r.events, [{ a: 1 }]);
});

test('ESC, C1 controls and bidi marks are dropped; tabs and newlines stay', () => {
  assert.equal(clean('a\x1b[31mred\u202Eb\u2066c\u200Fd\x9be\tf\ng\r'), 'a[31mredbcde\tf\ng');
});

// Each closed block is rendered once and frozen; only the open block is rendered again as chunks land.
test('an 8000-character reply in 200 chunks renders each closed block once', () => {
  const para = (i) => `Paragraph ${i} says ${'word '.repeat(40)}done.`;
  const parts = [];
  for (let i = 0; parts.join('\n\n').length < 8000; i++) {
    parts.push(para(i));
    if (i % 4 === 1) parts.push('```fish\nfor f in *\n    echo $f\nend\n```');
    if (i % 4 === 3) parts.push('- one\n- two\n- three');
  }
  const reply = parts.join('\n\n').slice(0, 8000);
  const renders = [];
  const b = blocks((block) => {
    renders.push(block);
    return block.text;
  });
  const size = Math.ceil(reply.length / 200);
  let shown = [];
  for (let at = size; at < reply.length + size; at += size) {
    const r = b.feed(reply.slice(0, at));
    // the frozen blocks before this chunk are the same objects after it
    shown.forEach((blk, i) => assert.equal(r.closed[i], blk));
    shown = r.closed.slice();
  }
  const closed = renders.filter((r) => r.closed);
  const starts = closed.map((r) => r.start);
  assert.equal(new Set(starts).size, starts.length, 'no closed block rendered twice');
  assert.equal(b.feed(reply).closed.length, closed.length);
  assert.ok(closed.length > 10);
  assert.ok(closed.some((r) => r.kind === 'code' && r.lang === 'fish' && r.text === 'for f in *\n    echo $f\nend'));
  assert.ok(closed.some((r) => r.kind === 'list'));
});

test('a reply of a paragraph, a code fence and a paragraph ends as three blocks', () => {
  const b = blocks();
  const r = b.end('Here is one:\n\n```fish\nfor f in *\n    echo $f\nend\n```\n\nRun it in a folder.');
  assert.deepEqual(
    r.closed.map((x) => [x.kind, x.text]),
    [
      ['p', 'Here is one:'],
      ['code', 'for f in *\n    echo $f\nend'],
      ['p', 'Run it in a folder.'],
    ],
  );
  assert.equal(r.open, null);
});

test('a code fence closes its block though no blank line follows, and a paragraph runs up to a fence', () => {
  const r = blocks().end('Try:\n```sh\nls\n```\nThen look.');
  assert.deepEqual(
    r.closed.map((x) => x.kind),
    ['p', 'code', 'p'],
  );
});

test('quotes, tables and headings are blocks of their own kind', () => {
  const r = blocks().end('# Title\n\n> said\n> twice\n\n| a | b |\n|---|---|\n| 1 | 2 |\n\ntext');
  assert.deepEqual(
    r.closed.map((x) => x.kind),
    ['heading', 'quote', 'table', 'p'],
  );
});

test('the default render escapes HTML and draws bold and inline code', () => {
  const r = blocks().end('a <b>x</b> & **bold** and `c<d`');
  assert.equal(r.closed[0].html, 'a &lt;b&gt;x&lt;/b&gt; &amp; <b>bold</b> and <code>c&lt;d</code>');
});

// A 1 MiB line laid out in one Text stalls the shell, so a long line draws cut while the block keeps its whole text to copy.
test('a line over 4000 characters draws cut and keeps its whole text', () => {
  const long = 'x'.repeat(1 << 20);
  const r = blocks().end(`before\n\n${long}\n\nafter`);
  assert.equal(r.closed[1].text.length, 1 << 20);
  assert.ok(r.closed[1].html.length < 4100);
  assert.match(r.closed[1].html, /…$/);
});

// A code fence draws through a PlainText Text, so its drawn text is cut as a paragraph's is, while the block keeps the whole code to copy.
test('a code block over 4000 characters a line, or 400 lines, draws cut and keeps its whole text', () => {
  const wide = blocks().end('see:\n\n```json\n' + 'x'.repeat(1 << 20) + '\n```').closed[1];
  assert.equal(wide.text.length, 1 << 20);
  assert.ok(wide.html.length < 4100);
  const tall = blocks().end('```\n' + 'line\n'.repeat(5000) + '```').closed[0];
  assert.equal(tall.text.split('\n').length, 5000);
  assert.ok(tall.html.split('\n').length <= 401);
  assert.match(tall.html, /…$/);
});

test('a code block draws its text as is, for a PlainText Text: no entities', () => {
  assert.equal(blocks().end('```\na < b && c\n```').closed[0].html, 'a < b && c');
});

test('a block draws at most 20000 characters however its lines fall', () => {
  const many = blocks().end(Array.from({ length: 100 }, () => 'w'.repeat(3000)).join(' \n')).closed[0];
  assert.ok(many.html.length < 21000, String(many.html.length));
});

test('bold and italics wrap inline code too', () => {
  assert.equal(blocks().end('**`set`** builtin and *`x`*').closed[0].html, '<b><code>set</code></b> builtin and <i><code>x</code></i>');
});
