import { test } from 'node:test';
import assert from 'node:assert/strict';
import { addEntry, parseStore, storeText, LIMIT, visible, group, clampSelected, filesOf, fileUri, uriList, chipLabel, dragPayload } from './notifs.mjs';

const entry = (n, app = 'notify-send') => ({ key: `k${n}`, app, summary: `n ${n}`, body: '', critical: false, time: 1000 + n, actions: [] });

test('the newest entry goes first', () => {
  const h = addEntry(addEntry([], entry(1)), entry(2));
  assert.deepEqual(h.map((e) => e.summary), ['n 2', 'n 1']);
});

test('the history keeps 200 entries and drops the oldest', () => {
  assert.equal(LIMIT, 200);
  let h = [];
  for (let i = 1; i <= 201; i++) h = addEntry(h, entry(i));
  assert.equal(h.length, 200);
  assert.equal(h[0].summary, 'n 201');
  assert.equal(h.at(-1).summary, 'n 2');
});

test('the store round-trips the history and Do Not Disturb', () => {
  const h = [entry(2), entry(1)];
  assert.deepEqual(parseStore(storeText({ dnd: true, history: h })), { dnd: true, history: h });
});

test('a missing, broken or foreign store reads as empty', () => {
  for (const text of ['', '{', '[]', '{"history":3}', 'null']) assert.deepEqual(parseStore(text), { dnd: false, history: [] });
});

test('a stored entry missing its fields is dropped, and a long store is cut to 200', () => {
  const many = Array.from({ length: 250 }, (_, i) => entry(250 - i));
  const s = parseStore(JSON.stringify({ dnd: 'yes', history: [{ app: 1 }, ...many] }));
  assert.equal(s.dnd, false);
  assert.equal(s.history.length, 200);
  assert.equal(s.history[0].summary, 'n 250');
});

const from = (app, summary, time, body = '') => ({ key: `${app}-${time}`, app, summary, body, critical: false, time, actions: [] });
const shape = (groups) => groups.map((g) => [g.app, g.entries.map((e) => e.summary)]);

test('each app gets one group, groups by their newest entry, entries newest first', () => {
  const history = [from('chat', 'c3', 50), from('mail', 'm2', 40), from('chat', 'c2', 30), from('mail', 'm1', 20), from('chat', 'c1', 10)];
  assert.deepEqual(shape(group(history)), [
    ['chat', ['c3', 'c2', 'c1']],
    ['mail', ['m2', 'm1']],
  ]);
  assert.deepEqual(shape(group([from('mail', 'm1', 20), from('chat', 'c1', 30)])), [
    ['chat', ['c1']],
    ['mail', ['m1']],
  ]);
});

test('search matches app, summary or body, ignoring case', () => {
  const history = [from('Chat', 'lunch?', 30), from('mail', 'Invoice', 20, 'due Friday'), from('mail', 'hello', 10)];
  const found = (q) => visible(history, q).map((e) => e.summary);
  assert.deepEqual(found(''), ['lunch?', 'Invoice', 'hello']);
  assert.deepEqual(found('CHAT'), ['lunch?']);
  assert.deepEqual(found('invoice'), ['Invoice']);
  assert.deepEqual(found('friday'), ['Invoice']);
  assert.deepEqual(found('nothing'), []);
});

test('the selection stays in range after a removal', () => {
  assert.equal(clampSelected(2, 2), 1);
  assert.equal(clampSelected(1, 3), 1);
  assert.equal(clampSelected(0, 0), 0);
  assert.equal(clampSelected(-1, 3), 0);
});

test('a store with entries sharing a key keeps only the first, so a dismiss takes one row', () => {
  const s = parseStore(JSON.stringify({ dnd: false, history: [entry(3), Object.assign(entry(2), { key: 'k3' }), entry(1)] }));
  assert.deepEqual(s.history.map((e) => e.summary), ['n 3', 'n 1']);
});

const HOME = '/home/saiful';

test('x-dots-files gives its path, URI and chip', () => {
  const files = filesOf({ 'x-dots-files': '/home/saiful/Downloads/IMG_2041.HEIC' }, HOME);
  assert.deepEqual(files, ['/home/saiful/Downloads/IMG_2041.HEIC']);
  assert.equal(fileUri(files[0]), 'file:///home/saiful/Downloads/IMG_2041.HEIC');
  assert.equal(chipLabel(files), 'HEIC');
  assert.equal(chipLabel(['/home/saiful/Downloads/README']), 'FILE');
});

test('a name with spaces, # and non-ASCII encodes per segment', () => {
  const path = '/home/saiful/Downloads/my photo #1 é.jpg';
  const uri = fileUri(path);
  assert.equal(uri, 'file:///home/saiful/Downloads/my%20photo%20%231%20%C3%A9.jpg');
  assert.equal(decodeURIComponent(uri.slice('file://'.length)), path);
});

test('an image-path that is not a user file gives no files', () => {
  for (const p of ['/tmp/chromium-xyz.png', '/usr/share/icons/hicolor/48x48/apps/x.png', '/usr/share/pixmaps/x.png', HOME + '/.local/share/icons/x.png', HOME + '/.icons/x.png', 'dialog-information', '/home/saiful/../tmp/x']) {
    assert.deepEqual(filesOf({ 'image-path': p }, HOME), [], p);
  }
});

test('an image-path file URI is decoded, and image_path works too', () => {
  const want = ['/home/saiful/Pictures/Screenshots/Screenshot from 2026.png'];
  assert.deepEqual(filesOf({ 'image-path': 'file:///home/saiful/Pictures/Screenshots/Screenshot%20from%202026.png' }, HOME), want);
  assert.deepEqual(filesOf({ image_path: '/home/saiful/Pictures/a.png' }, HOME), ['/home/saiful/Pictures/a.png']);
});

test('x-dots-files wins over image-path and skips blank, relative and /tmp lines', () => {
  const hints = { 'x-dots-files': '/home/saiful/Downloads/a.txt\n\nrel/b.txt\n/tmp/c.txt\n/home/saiful/Downloads/d.txt', 'image-path': '/home/saiful/Pictures/x.png' };
  assert.deepEqual(filesOf(hints, HOME), ['/home/saiful/Downloads/a.txt', '/home/saiful/Downloads/d.txt']);
});

test('three files give a CRLF uri-list and a count chip', () => {
  const files = filesOf({ 'x-dots-files': '/home/saiful/Downloads/a.txt\n/home/saiful/Downloads/b b.txt\n/home/saiful/Downloads/c.txt' }, HOME);
  assert.equal(files.length, 3);
  assert.equal(uriList(files), 'file:///home/saiful/Downloads/a.txt\r\nfile:///home/saiful/Downloads/b%20b.txt\r\nfile:///home/saiful/Downloads/c.txt\r\n');
  assert.equal(chipLabel(files), '3 FILES');
});

test('an entry drags its files as a uri-list, else its body as text', () => {
  assert.deepEqual(dragPayload({ body: 'hi', files: ['/home/saiful/Downloads/a.txt'] }), { mime: 'text/uri-list', data: 'file:///home/saiful/Downloads/a.txt\r\n' });
  assert.deepEqual(dragPayload({ body: 'hi' }), { mime: 'text/plain', data: 'hi' });
  assert.deepEqual(dragPayload({ body: 'hi', files: [] }), { mime: 'text/plain', data: 'hi' });
});

test('parseStore keeps a valid files array and drops a malformed one', () => {
  const good = Object.assign(entry(1), { files: ['/home/saiful/Downloads/a.txt'] });
  assert.deepEqual(parseStore(storeText({ dnd: false, history: [good] })).history, [good]);
  for (const files of ['/home/saiful/a', ['rel/a'], ['/a', 3], [null]]) {
    const h = parseStore(JSON.stringify({ history: [Object.assign(entry(2), { files })] })).history;
    assert.equal(h.length, 1);
    assert.equal('files' in h[0], false);
  }
});
