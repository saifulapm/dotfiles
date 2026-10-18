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

import { TAGS, toggleTag, deleteNotes, merge, moveNotes, toggleDone, editNote, search, sectionNames, sectionList, ATTACH_MAX, attachRefusal, attach, attachmentFile, dragOffer, chipOffer } from './notes.mjs';

const PNG = { sha256: 'abc123', name: 'shot.PNG', mime: 'image/png', size: 10 };
const mk = (id, fields) => Object.assign({ id, section: 'inbox', text: id, attachments: [], todo: false, done: false, tags: [], createdAt: T, updatedAt: T }, fields);
const storeOf = (notes, sections) => Object.assign(emptyStore(), { notes, sections: sections || emptyStore().sections });
// Runs a rule and checks it left its input untouched.
const pure = (store, fn) => {
  const before = structuredClone(store);
  const out = fn(store);
  assert.deepEqual(store, before);
  return out;
};

test('merging joins texts, attachments and tags into the first note and tombstones the rest', () => {
  const s = storeOf([mk('a', { tags: ['red'] }), mk('b', { attachments: [PNG], tags: ['blue'] })]);
  const r = pure(s, (x) => merge(x, ['a', 'b'], T + 9));
  assert.equal(r.notes.length, 2);
  assert.deepEqual(r.notes[0], mk('a', { text: 'a\n\nb', attachments: [PNG], tags: ['red', 'blue'], updatedAt: T + 9 }));
  assert.deepEqual(r.notes[1], { id: 'b', section: 'inbox', text: '', attachments: [], todo: false, done: false, tags: [], createdAt: T, updatedAt: T + 9, deleted: true });
});

test('merging keeps a shared attachment once and needs two live notes', () => {
  const s = storeOf([mk('a', { attachments: [PNG] }), mk('b', { attachments: [PNG] }), mk('c', { deleted: true })]);
  assert.equal(merge(s, ['a', 'b'], T + 1).notes[0].attachments.length, 1);
  for (const ids of [['a'], [], ['a', 'c'], ['a', 'zz']]) assert.deepEqual(pure(s, (x) => merge(x, ids, T + 1)), s);
});

test('merging takes todo from any note and done from every to-do', () => {
  const s = storeOf([mk('a', { todo: true, done: true }), mk('b'), mk('c', { todo: true, done: true })]);
  const m = merge(s, ['a', 'b', 'c'], T + 1).notes[0];
  assert.deepEqual([m.todo, m.done], [true, true]);
  const m2 = merge(storeOf([mk('a', { todo: true, done: true }), mk('b', { todo: true })]), ['a', 'b'], T + 1).notes[0];
  assert.deepEqual([m2.todo, m2.done], [true, false]);
  const m3 = merge(storeOf([mk('a'), mk('b')]), ['a', 'b'], T + 1).notes[0];
  assert.deepEqual([m3.todo, m3.done], [false, false]);
});

test('merging follows the order of the ids given', () => {
  const s = storeOf([mk('a'), mk('b')]);
  const r = merge(s, ['b', 'a'], T + 1);
  assert.equal(r.notes[1].text, 'b\n\na');
  assert.equal(r.notes[0].deleted, true);
});

test('a tag key toggles its colour in tag order', () => {
  assert.deepEqual(TAGS, ['red', 'orange', 'yellow', 'green', 'blue', 'purple']);
  let s = storeOf([mk('a', { tags: ['blue'] })]);
  s = pure(s, (x) => toggleTag(x, 'a', '3', T + 1));
  assert.deepEqual(s.notes[0].tags, ['yellow', 'blue']);
  assert.equal(s.notes[0].updatedAt, T + 1);
  assert.deepEqual(toggleTag(s, 'a', '3', T + 2).notes[0].tags, ['blue']);
  for (const k of ['7', 'x', '0']) assert.equal(toggleTag(s, 'a', k, T + 2), s);
});

test('deleting leaves tombstones in the store', () => {
  const s = storeOf([mk('a', { text: 'hi', attachments: [PNG], tags: ['red'], todo: true, done: true }), mk('b')]);
  const r = pure(s, (x) => deleteNotes(x, ['a'], T + 4));
  assert.deepEqual(r.notes[0], { id: 'a', section: 'inbox', text: '', attachments: [], todo: false, done: false, tags: [], createdAt: T, updatedAt: T + 4, deleted: true });
  assert.deepEqual(r.notes[1], s.notes[1]);
});

test('moving notes creates a missing section with the next order', () => {
  const s = storeOf([mk('a'), mk('b')]);
  const r = pure(s, (x) => moveNotes(x, ['a'], 'prompts', T + 1));
  assert.deepEqual(r.sections, [{ name: 'inbox', order: 0 }, { name: 'prompts', order: 1 }]);
  assert.deepEqual([r.notes[0].section, r.notes[0].updatedAt, r.notes[1].section], ['prompts', T + 1, 'inbox']);
  assert.equal(r.activeSection, 'inbox');
  assert.equal(moveNotes(r, ['b'], 'prompts', T + 2).sections.length, 2);
});

test('done toggles a to-do and turns a plain note into one', () => {
  let s = storeOf([mk('a')]);
  s = pure(s, (x) => toggleDone(x, 'a', T + 1));
  assert.deepEqual([s.notes[0].todo, s.notes[0].done], [true, false]);
  s = toggleDone(s, 'a', T + 2);
  assert.deepEqual([s.notes[0].todo, s.notes[0].done], [true, true]);
  assert.equal(toggleDone(s, 'a', T + 3).notes[0].done, false);
});

test('editing replaces the text and ignores an empty one', () => {
  const s = storeOf([mk('a')]);
  const r = pure(s, (x) => editNote(x, 'a', 'new text', T + 1));
  assert.deepEqual([r.notes[0].text, r.notes[0].updatedAt], ['new text', T + 1]);
  for (const t of ['', '  \n']) assert.equal(editNote(s, 'a', t, T + 1), s);
});

test('search finds text in every section, newest first, skipping tombstones', () => {
  const s = storeOf(
    [mk('a', { text: 'An Island trip', createdAt: T }), mk('b', { section: 'other', text: 'island', createdAt: T + 1 }), mk('c', { text: 'island', deleted: true }), mk('d', { text: 'sea' })],
    [{ name: 'inbox', order: 0 }, { name: 'other', order: 1 }]
  );
  assert.deepEqual(pure(s, (x) => search(x, 'ISLAND')).map((n) => n.id), ['b', 'a']);
  assert.deepEqual(search(s, ''), []);
});

test('section names come in section order', () => {
  const s = storeOf([], [{ name: 'b', order: 1 }, { name: 'a', order: 0 }]);
  assert.deepEqual(pure(s, sectionNames), ['a', 'b']);
});

test('a section renders as a Markdown list', () => {
  const s = storeOf([
    mk('a', { text: 'plain', createdAt: T }),
    mk('b', { text: 'todo', todo: true, createdAt: T + 1 }),
    mk('c', { text: 'finished', todo: true, done: true, createdAt: T + 2 }),
    mk('d', { text: 'one\ntwo', createdAt: T + 3 }),
    mk('e', { text: 'gone', deleted: true, createdAt: T + 4 }),
    mk('f', { section: 'other', text: 'else', createdAt: T + 5 }),
  ]);
  assert.equal(pure(s, (x) => sectionList(x, 'inbox')), '- one\n  two\n- [x] finished\n- [ ] todo\n- plain');
});

test('an attachment over 25 MB is refused', () => {
  assert.equal(ATTACH_MAX, 25 * 1024 * 1024);
  assert.equal(attachRefusal(26 * 1024 * 1024), 'Attachment over 25 MB');
  assert.equal(attachRefusal(ATTACH_MAX), null);
});

test('attaching adds a file once per sha256', () => {
  const s = storeOf([mk('a')]);
  const r = pure(s, (x) => attach(x, 'a', PNG, T + 1));
  assert.deepEqual([r.notes[0].attachments, r.notes[0].updatedAt], [[PNG], T + 1]);
  assert.deepEqual(attach(r, 'a', PNG, T + 2).notes[0].attachments, [PNG]);
});

test('an attachment file is named by hash and extension', () => {
  assert.equal(attachmentFile(PNG), 'abc123.png');
  assert.equal(attachmentFile({ sha256: 'h', name: 'noext', mime: 'image/png' }), 'h.png');
  assert.equal(attachmentFile({ sha256: 'h', name: 'x', mime: 'image/jpeg' }), 'h.jpg');
  assert.equal(attachmentFile({ sha256: 'h', name: 'x', mime: 'application/zip' }), 'h.bin');
});

test('dragging offers one format only', () => {
  assert.deepEqual(dragOffer(mk('a', { text: 'hi', attachments: [PNG] })), { 'text/plain': 'hi' });
  assert.deepEqual(chipOffer(PNG, '/d/files'), { 'text/uri-list': 'file:///d/files/abc123.png' });
});
