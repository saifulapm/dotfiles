import { test } from 'node:test';
import assert from 'node:assert/strict';
import { CALLS_MAX, RESULT_MAX, TOOLS, argvFor, chipFor, cut, take } from './chat-tools.mjs';

const bytes = (s) => Buffer.byteLength(s, 'utf8');

test('TOOLS lists the three read-only mem tools with required string params', () => {
  assert.deepEqual(
    TOOLS.map((t) => [t.type, t.function.name, t.function.parameters.required]),
    [
      ['function', 'mem_search', ['query']],
      ['function', 'mem_show', ['id']],
      ['function', 'mem_wiki', ['project', 'slug']],
    ],
  );
  for (const t of TOOLS) {
    assert.ok(t.function.description.length > 0);
    for (const p of Object.values(t.function.parameters.properties)) assert.equal(p.type, 'string');
  }
});

test('argvFor builds the exact argv for each tool', () => {
  assert.deepEqual(argvFor('mem_search', '{"query":"island shape"}'), { argv: ['search', '--scope', 'all', 'island shape'] });
  assert.deepEqual(argvFor('mem_show', '{"id":"abc123"}'), { argv: ['show', 'abc123'] });
  assert.deepEqual(argvFor('mem_wiki', '{"project":"dotfiles","slug":"spec"}'), { argv: ['--project', 'dotfiles', 'wiki', 'spec'] });
});

test('a query with shell characters stays one argv element', () => {
  assert.deepEqual(argvFor('mem_search', JSON.stringify({ query: 'x; touch PWNED' })), { argv: ['search', '--scope', 'all', 'x; touch PWNED'] });
});

test('argvFor refuses what must never run', () => {
  const bad = [
    ['mem_search', '{"query":"--stdin"}'],
    ['mem_show', '{"id":"--stdin"}'],
    ['mem_wiki', '{"project":"dotfiles","slug":"--stdin"}'],
    ['mem_wiki', '{"project":"-x","slug":"spec"}'],
    ['web_search', '{"query":"x"}'],
    ['mem_decide', '{"query":"x"}'],
    ['mem_search', '{"query":'],
    ['mem_search', ''],
    ['mem_search', 'null'],
    ['mem_search', '{}'],
    ['mem_search', '{"query":5}'],
    ['mem_search', '{"query":""}'],
    ['mem_wiki', '{"project":"dotfiles"}'],
    ['mem_search', '{"query":"a\\nb"}'],
    ['mem_search', '{"query":"a\\u0000b"}'],
    ['mem_search', JSON.stringify({ query: 'x'.repeat(201) })],
  ];
  for (const [name, args] of bad) {
    const r = argvFor(name, args);
    assert.equal(r.argv, undefined, `${name} ${args}`);
    assert.equal(typeof r.error, 'string', `${name} ${args}`);
    assert.ok(r.error.length > 0 && !r.error.includes('\n'));
  }
  assert.deepEqual(argvFor('mem_search', JSON.stringify({ query: 'x'.repeat(200) })).argv.length, 4);
});

test('no argv ever carries a writing mem command word in command position', () => {
  const writing = ['decide', 'ask', 'answer', 'plan', 'roadmap', 'log', 'idea', 'finding', 'handoff', '--stdin'];
  const calls = [
    ['mem_search', { query: 'decide' }],
    ['mem_show', { id: 'log' }],
    ['mem_wiki', { project: 'plan', slug: 'handoff' }],
    ['mem_wiki', { project: 'dotfiles', slug: 'decide' }],
  ];
  for (const [name, args] of calls) {
    const { argv } = argvFor(name, JSON.stringify(args));
    const pos = argv[0] === '--project' ? 2 : 0;
    assert.ok(['search', 'show', 'wiki'].includes(argv[pos]));
    assert.ok(!writing.includes(argv[pos]));
  }
  assert.equal(argvFor('mem_wiki', '{"project":"--stdin","slug":"x"}').argv, undefined);
});

test('chipFor gives the name and its muted argument', () => {
  assert.deepEqual(chipFor('mem_search', '{"query":"island shape"}'), { name: 'mem_search', arg: 'island shape' });
  assert.deepEqual(chipFor('mem_show', '{"id":"abc123"}'), { name: 'mem_show', arg: 'abc123' });
  assert.deepEqual(chipFor('mem_wiki', '{"project":"dotfiles","slug":"spec"}'), { name: 'mem_wiki', arg: 'dotfiles · spec' });
  assert.deepEqual(chipFor('mem_search', '{oops'), { name: 'mem_search', arg: '' });
});

test('cut keeps a result within 8192 UTF-8 bytes', () => {
  assert.equal(RESULT_MAX, 8192);
  assert.equal(cut('short'), 'short');
  const out = cut('a'.repeat(20 * 1024));
  assert.ok(bytes(out) <= 8192);
  assert.ok(bytes(out) > 8000);
});

test('cut never splits a multi-byte character', () => {
  for (const unit of ['আ', '😀', 'é']) {
    const out = cut(unit.repeat(5000));
    assert.ok(bytes(out) <= 8192, unit);
    assert.ok(!out.includes('�'));
    const body = out.replace(/\n…\(cut\)$/, '');
    assert.equal(body, unit.repeat(body.length / unit.length));
  }
});

test('take runs at most 10 calls a turn', () => {
  assert.equal(CALLS_MAX, 10);
  const calls = Array.from({ length: 11 }, (_, i) => i);
  assert.deepEqual(take(calls, 0), { run: calls.slice(0, 10), skipped: [10] });
  assert.deepEqual(take(calls, 9), { run: [0], skipped: calls.slice(1) });
  assert.deepEqual(take([1, 2], 10), { run: [], skipped: [1, 2] });
  assert.deepEqual(take([1, 2], 0), { run: [1, 2], skipped: [] });
});
