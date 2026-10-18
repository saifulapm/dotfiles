import { test } from 'node:test';
import assert from 'node:assert/strict';
import { emptyStore, parseStore, machineId, sectionCommand, compose, capture, lastCapture, sectionNotes, CAPTURE_MAX } from './notes.mjs';

const T = 1760000000000;

test('a new store has one inbox section and no notes', () => {
  assert.deepEqual(emptyStore(), { version: 1, activeSection: 'inbox', sections: [{ name: 'inbox', order: 0 }], notes: [] });
});

test('a missing or broken store file reads as a new store', () => {
  for (const t of ['', '{', '[]', 'null', '{"version":1}']) assert.deepEqual(parseStore(t), emptyStore());
  const s = Object.assign(emptyStore(), { notes: [{ id: 'a', section: 'inbox', text: 'x' }] });
  assert.equal(parseStore(JSON.stringify(s)).notes[0].text, 'x');
});

test('the machine id is DOTS_MACHINE, then chezmoi data, then the hostname', () => {
  const toml = '# comment\nsourceDir = "~/x"\n\n[data]\n    machine = "macbook-m2"\n';
  assert.equal(machineId('dev', toml, 'host\n'), 'dev');
  assert.equal(machineId('', toml, 'host\n'), 'macbook-m2');
  assert.equal(machineId('', '', 'host\n'), 'host');
  assert.equal(machineId('', '', ''), 'unknown');
  // An id names a file, so a path in one is never used.
  assert.equal(machineId('../x', '', 'host'), 'host');
});

test('a composed note that is exactly # Name is a section command', () => {
  assert.equal(sectionCommand('# prompts'), 'prompts');
  assert.equal(sectionCommand('  # two words  '), 'two words');
  for (const t of ['#prompts', '# ', 'x\n# prompts', '# a\nb', '## h']) assert.equal(sectionCommand(t), null);
});

test('composing # Name creates the section once and makes it active', () => {
  let s = compose(emptyStore(), '# prompts', T, 'n1');
  assert.equal(s.activeSection, 'prompts');
  assert.deepEqual(s.sections, [{ name: 'inbox', order: 0 }, { name: 'prompts', order: 1 }]);
  assert.equal(s.notes.length, 0);
  s = compose(compose(s, '# inbox', T, 'n2'), '# prompts', T, 'n3');
  assert.equal(s.activeSection, 'prompts');
  assert.equal(s.sections.length, 2);
});

test('composing text adds a note to the active section', () => {
  const s = compose(compose(emptyStore(), '# prompts', T, 'n1'), 'line one\nline two', T + 5, 'n2');
  assert.deepEqual(s.notes, [{ id: 'n2', section: 'prompts', text: 'line one\nline two', attachments: [], todo: false, done: false, tags: [], createdAt: T + 5, updatedAt: T + 5 }]);
  assert.equal(compose(s, '   ', T, 'n3'), s);
});

test('a capture adds the selection to the active section and says Captured', () => {
  const s0 = compose(emptyStore(), '# prompts', T, 'n0');
  const r = capture(s0, 'hello capture', '', T, 'c1');
  assert.equal(r.toast, 'Captured');
  assert.deepEqual([r.store.notes[0].text, r.store.notes[0].section], ['hello capture', 'prompts']);
  assert.equal(r.last, 'hello capture');
});

test('the same selection twice makes one note and says Already captured', () => {
  const r1 = capture(emptyStore(), 'same', '', T, 'c1');
  const r2 = capture(r1.store, 'same', r1.last, T + 1, 'c2');
  assert.equal(r2.toast, 'Already captured');
  assert.equal(r2.store, r1.store);
  // A shell restart forgets the last capture, so it is read back from the newest note.
  assert.equal(lastCapture(r1.store), 'same');
  assert.equal(capture(r1.store, 'same', lastCapture(r1.store), T + 2, 'c3').toast, 'Already captured');
});

test('an empty selection says Nothing selected and adds no note', () => {
  for (const sel of ['', '  \n']) {
    const r = capture(emptyStore(), sel, '', T, 'c1');
    assert.equal(r.toast, 'Nothing selected');
    assert.equal(r.store.notes.length, 0);
  }
});

test('a capture is cut at 10,000 characters', () => {
  const r = capture(emptyStore(), 'x'.repeat(12000), '', T, 'c1');
  assert.equal(CAPTURE_MAX, 10000);
  assert.equal(r.store.notes[0].text.length, 10000);
  assert.equal(capture(r.store, 'x'.repeat(11000), r.last, T, 'c2').toast, 'Already captured');
});

test('a section lists its live notes newest first', () => {
  let s = compose(emptyStore(), 'old', T, 'a');
  s = compose(s, 'new', T + 1, 'b');
  s = compose(compose(s, '# other', T, 'x'), 'elsewhere', T + 2, 'c');
  s = Object.assign({}, s, { notes: s.notes.concat([{ id: 'd', section: 'inbox', text: 'gone', deleted: true, createdAt: T + 3 }]) });
  assert.deepEqual(sectionNotes(s, 'inbox').map((n) => n.text), ['new', 'old']);
});
