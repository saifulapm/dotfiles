import { test } from 'node:test';
import assert from 'node:assert/strict';
import { parseQuestions, shown, optionFor, answerArgv } from './questions.mjs';

const q = (id, extra = {}) => Object.assign({ id, project: 'dotfiles', machine: 'mini.taila27604.ts.net:8790', text: `${id}?`, options: ['Import now', 'Later'], popup: true }, extra);
const file = (...qs) => JSON.stringify({ self: 'macbook', questions: qs });

test('the hub file reads as its questions, with the machine cut to its first label', () => {
  const [a] = parseQuestions(file(q('Q1')));
  assert.deepEqual(a, { id: 'Q1', project: 'dotfiles', machine: 'mini', text: 'Q1?', options: ['Import now', 'Later'], popup: true });
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
  assert.deepEqual(answerArgv('Q1', '-rf now'), ['mem', 'answer', '--by', 'island', '--', 'Q1', '-rf now']);
});
