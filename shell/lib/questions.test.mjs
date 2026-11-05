import { test } from 'node:test';
import assert from 'node:assert/strict';
import { parseQuestions, shown, optionFor, answerArgv, summary, linkify, baseName } from './questions.mjs';

const q = (id, extra = {}) => Object.assign({ id, project: 'dotfiles', machine: 'mini.taila27604.ts.net:8790', text: `${id}?`, options: ['Import now', 'Later'], popup: true }, extra);
const file = (...qs) => JSON.stringify({ self: 'macbook', questions: qs });

test('the hub file reads as its questions, with the machine cut to its first label', () => {
  const [a] = parseQuestions(file(q('Q1')));
  assert.deepEqual(a, { id: 'Q1', project: 'dotfiles', machine: 'mini', text: 'Q1?', options: ['Import now', 'Later'], recommend: '', popup: true });
});

test('a missing, broken or foreign file has no questions, and bad entries are skipped', () => {
  for (const t of ['', '{', '[]', '{"questions":3}']) assert.deepEqual(parseQuestions(t), []);
  const qs = parseQuestions(JSON.stringify({ questions: [null, { id: '' }, { id: 7 }, { id: 'Q2', options: ['a', 3, 'b'] }] }));
  assert.deepEqual(qs.map((x) => [x.id, x.options, x.text, x.popup]), [['Q2', ['a', 'b'], '', false]]);
});

test('the island shows the first question that rings here and is not put away', () => {
  const qs = parseQuestions(file(q('Q1', { popup: false }), q('Q2'), q('Q3')));
  assert.equal(shown(qs, {}).id, 'Q2');
  assert.equal(shown(qs, { Q2: true }).id, 'Q3');
  assert.equal(shown(qs, { Q2: true, Q3: true }), null);
});

test('keys 1 to 9 pick an option, and other keys pick none', () => {
  const [a] = parseQuestions(file(q('Q1')));
  assert.equal(optionFor(a, '1'), 'Import now');
  assert.equal(optionFor(a, '2'), 'Later');
  assert.equal(optionFor(a, '3'), null);
  assert.equal(optionFor(a, '0'), null);
  assert.equal(optionFor(a, 'x'), null);
  assert.equal(optionFor(a, ''), null);
  assert.equal(optionFor(a, '12'), null);
});

test('an answer travels as argv after --, so a leading dash stays text', () => {
  assert.deepEqual(answerArgv('Q1', '-rf now'), ['mem', 'answer', '--by', 'popup', '--', 'Q1', '-rf now']);
});

test('attachments go to mem answer as --screenshot paths, before the --', () => {
  assert.deepEqual(answerArgv('Q1', 'see these', ['/run/a b.png', '-x.pdf']), ['mem', 'answer', '--by', 'popup', '--screenshot', '/run/a b.png', '--screenshot', '-x.pdf', '--', 'Q1', 'see these']);
  assert.equal(baseName('/home/s/Downloads/report.pdf'), 'report.pdf');
});

test('the hub\'s recommend is kept, and the closed card sums the options up', () => {
  const [a, b, c] = parseQuestions(file(q('Q1', { recommend: 'Later' }), q('Q2', { recommend: null, options: ['Only'] }), q('Q3', { options: [] })));
  assert.equal(a.recommend, 'Later');
  assert.equal(b.recommend, '');
  assert.equal(summary(a), '2 options · ★ Later');
  assert.equal(summary(b), '1 option');
  assert.equal(summary(c), 'No options · r to reply');
});

test('web addresses become links by number, and everything else stays escaped text', () => {
  const l = linkify('Search Reshoot at curseforge.com/minecraft/search (agents get a 403). See https://x.dev/a?b=1&c=2, then wrangler.jsonc.');
  assert.deepEqual(l.urls, ['https://curseforge.com/minecraft/search', 'https://x.dev/a?b=1&c=2']);
  assert.equal(l.html, 'Search Reshoot at <a href="0">curseforge.com/minecraft/search</a> (agents get a 403). See <a href="1">https://x.dev/a?b=1&amp;c=2</a>, then wrangler.jsonc.');
});

test('markup, other schemes, file names, paths and mail addresses are never links', () => {
  const l = linkify('<b>hi</b> javascript:alert(1) file:///etc/passwd deploy.yml corde-desktop.jpg ~/.cache/tambour-m19/release saiful@example.com 0058-0061 & "q"');
  assert.deepEqual(l.urls, []);
  assert.equal(l.html, '&lt;b&gt;hi&lt;/b&gt; javascript:alert(1) file:///etc/passwd deploy.yml corde-desktop.jpg ~/.cache/tambour-m19/release saiful@example.com 0058-0061 &amp; &quot;q&quot;');
});

test('a link in parentheses leaves the closing parenthesis out, and new lines stay lines', () => {
  const l = linkify('URL (https://eventsmith.lareys.dev) and api.ebdfy.com.\nNext');
  assert.deepEqual(l.urls, ['https://eventsmith.lareys.dev', 'https://api.ebdfy.com']);
  assert.equal(l.html, 'URL (<a href="0">https://eventsmith.lareys.dev</a>) and <a href="1">api.ebdfy.com</a>.<br>Next');
});
