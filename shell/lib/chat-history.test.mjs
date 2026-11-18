import { test } from 'node:test';
import assert from 'node:assert/strict';
import { KEEP, fileName, parse, prune, rows, serialize, title } from './chat-history.mjs';

test('fileName is a safe name that sorts by time', () => {
  assert.equal(fileName(Date.UTC(2026, 10, 18, 22, 15, 3, 123)), '2026-11-18T22-15-03-123Z.json');
  const a = fileName(Date.UTC(2026, 0, 2));
  const b = fileName(Date.UTC(2026, 10, 18));
  assert.ok(a < b);
});

const conv = {
  start: 1000,
  title: 'T',
  alias: 'fast',
  model: 'm',
  messages: [
    {
      role: 'user',
      content: 'look',
      attachments: [
        { name: 'a.png', size: 10, kind: 'image', data: 'data:image/png;base64,iVBORw0KGgo' },
        { name: 'n.txt', size: 5, kind: 'text', text: 'SECRET file text' },
      ],
    },
    { role: 'assistant', content: 'ok', tools: [{ name: 'mem_show', arg: 'x', result: 'BIG' }], extra: 1 },
  ],
};

test('serialize keeps names and sizes but no file bytes or text', () => {
  const s = serialize(conv);
  assert.ok(!s.includes('base64'));
  assert.ok(!s.includes('SECRET'));
  assert.ok(!s.includes('BIG'));
  assert.deepEqual(JSON.parse(s), {
    start: 1000,
    title: 'T',
    alias: 'fast',
    model: 'm',
    messages: [
      { role: 'user', content: 'look', attachments: [{ name: 'a.png', size: 10, kind: 'image' }, { name: 'n.txt', size: 5, kind: 'text' }] },
      { role: 'assistant', content: 'ok', tools: [{ name: 'mem_show', arg: 'x' }] },
    ],
  });
});

test('parse round-trips and skips broken files', () => {
  assert.equal(parse('not json'), null);
  assert.equal(parse('{"x":1}'), null);
  assert.equal(parse('{"start":"1","messages":[]}'), null);
  assert.equal(parse('{"start":1,"messages":{}}'), null);
  assert.equal(parse('null'), null);
  assert.equal(parse(serialize(conv)).start, 1000);
});

test('prune names the oldest files beyond KEEP and ignores other names', () => {
  assert.equal(KEEP, 50);
  const names = Array.from({ length: 51 }, (_, i) => fileName(Date.UTC(2026, 0, 1, 0, i)));
  assert.deepEqual(prune([...names].reverse()), [names[0]]);
  assert.deepEqual(prune(names.slice(1)), []);
  assert.deepEqual(prune([...names, 'notes.txt', '.hidden']), [names[0]]);
  const many = [...names, fileName(Date.UTC(2026, 1, 1)), fileName(Date.UTC(2026, 1, 2))];
  assert.deepEqual(prune(many), names.slice(0, 3));
});

test('title is the first user line, trimmed and cut to 60', () => {
  const m = (content) => ({ messages: [{ role: 'assistant', content: 'hi' }, { role: 'user', content }] });
  assert.equal(title(m('  how does the island work?  \nsecond')), 'how does the island work?');
  assert.equal(title(m('x'.repeat(70))), 'x'.repeat(60) + '…');
  assert.equal(title(m('x'.repeat(60))), 'x'.repeat(60));
  assert.equal(title({ messages: [] }), 'New chat');
  assert.equal(title(m('   ')), 'New chat');
});

test('rows lists newest first with a question and an age', () => {
  const now = 10 * 86400 * 1000;
  const user = (content) => [{ role: 'user', content }];
  const list = [
    { file: 'a.json', start: now - 30 * 1000, title: 'A', messages: user('first\nsecond') },
    { file: 'b.json', start: now - 5 * 60 * 1000, title: 'B', messages: user('q'.repeat(100)) },
    { file: 'c.json', start: now - 3 * 3600 * 1000, title: 'C', messages: [] },
    { file: 'd.json', start: now - 2 * 86400 * 1000, title: 'D', messages: user('old') },
  ];
  assert.deepEqual(rows([list[3], list[1], list[0], list[2]], now), [
    { file: 'a.json', start: now - 30000, title: 'A', question: 'first', age: 'now' },
    { file: 'b.json', start: now - 300000, title: 'B', question: 'q'.repeat(80) + '…', age: '5 min' },
    { file: 'c.json', start: now - 10800000, title: 'C', question: '', age: '3 h' },
    { file: 'd.json', start: now - 172800000, title: 'D', question: 'old', age: '2 d' },
  ]);
});
