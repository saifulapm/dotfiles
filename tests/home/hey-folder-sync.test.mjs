// bin/hey-folder-sync --apply against a real scratch notmuch store: mail another machine filed stays filed, and a failed retag is retried rather than undone.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { chmodSync, mkdirSync, readdirSync, renameSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { mailRig, me, repo } from './mail-rig.mjs';

const script = join(repo, 'bin/hey-folder-sync');

function heyRig(t) {
  const rig = mailRig(t);
  const box = (f) => join(rig.mail, 'icloud', f);
  for (const f of ['HEY/ReplyLater']) for (const s of ['new', 'cur', 'tmp']) mkdirSync(join(box(f), s), { recursive: true });
  rig.setDb('foldersync.db', 'HEY/ReplyLater\n');
  const sync = (env = rig.env, ...args) => {
    const r = rig.run(script, args, { env });
    assert.equal(r.status, 0, r.stderr);
    return r.stdout;
  };
  const files = (f) => ['new', 'cur'].flatMap((s) => readdirSync(join(box(f), s)));
  const tags = (id) => rig.notmuch('search', '--exclude=false', '--output=tags', '--', `id:${id}`).trim().split('\n');
  // Writes a plain-text mail straight into FOLDER, as mbsync would after another client filed it there.
  const arrive = (folder, id, name) => {
    writeFileSync(join(box(folder), 'new', name), `From: Ann <ann@people.test>\nTo: ${me}\nSubject: hi\nDate: Sat, 14 Nov 2026 10:00:00 +0000\nMessage-ID: <${id}>\n\nhello\n`);
    rig.notmuch('new', '--quiet');
  };
  return { ...rig, box, sync, files, tags, arrive };
}

test('a mail first seen in an enabled HEY folder takes its tags and stays there', (t) => {
  const r = heyRig(t);
  assert.equal(r.sync(r.env, '--apply'), '0 0\n');
  r.arrive('HEY/ReplyLater', 'later@x.test', 'later.eml');
  // The post-new hook screens a known sender; that alone would put it in INBOX.
  r.notmuch('tag', '+screened', '--', 'id:later@x.test');

  assert.equal(r.sync(r.env, '--apply'), '0 0\n');

  assert.ok(r.tags('later@x.test').includes('replylater'));
  assert.deepEqual(r.files('HEY/ReplyLater'), ['later.eml']);
  assert.deepEqual(r.files('INBOX'), []);
});

test('a failed retag keeps the old folder in the state and the move is retried, not undone', (t) => {
  const r = heyRig(t);
  r.arrive('INBOX', 'moved@x.test', 'moved.eml');
  r.notmuch('tag', '+screened', '--', 'id:moved@x.test');
  assert.equal(r.sync(r.env, '--apply'), '0 0\n');
  assert.equal(r.sync(r.env, '--state'), 'id:moved@x.test\tINBOX\n');

  renameSync(join(r.box('INBOX'), 'new', 'moved.eml'), join(r.box('HEY/ReplyLater'), 'new', 'moved.eml'));
  r.notmuch('new', '--quiet');
  const stub = join(r.M, 'stub');
  mkdirSync(stub);
  writeFileSync(join(stub, 'notmuch'), '#!/bin/sh\n[ "$1" = tag ] && exit 1\nexec /usr/bin/notmuch "$@"\n');
  chmodSync(join(stub, 'notmuch'), 0o755);
  const failing = { ...r.env, PATH: `${stub}:${r.env.PATH}` };

  assert.equal(r.sync(failing, '--apply'), '0 0\n');
  assert.deepEqual(r.files('HEY/ReplyLater'), ['moved.eml']);
  assert.equal(r.sync(r.env, '--state'), 'id:moved@x.test\tINBOX\n');

  assert.equal(r.sync(r.env, '--apply'), '0 0\n');
  assert.ok(r.tags('moved@x.test').includes('replylater'));
  assert.deepEqual(r.files('HEY/ReplyLater'), ['moved.eml']);
  assert.equal(r.sync(r.env, '--state'), 'id:moved@x.test\tHEY/ReplyLater\n');
});

// The phone's tags for the folder say less than the mail's own: Paper Trail's would add ledger/unfiled beside the vendor.
test('a mail first seen in an enabled HEY folder its own tags already file there keeps its tags', (t) => {
  const r = heyRig(t);
  for (const s of ['new', 'cur', 'tmp']) mkdirSync(join(r.box('HEY/PaperTrail'), s), { recursive: true });
  r.setDb('foldersync.db', 'HEY/ReplyLater\nHEY/PaperTrail\n');
  assert.equal(r.sync(r.env, '--apply'), '0 0\n');
  r.arrive('HEY/PaperTrail', 'bill@x.test', 'bill.eml');
  r.notmuch('tag', '+ledger/acme', '+archived', '-inbox', '--', 'id:bill@x.test');

  assert.equal(r.sync(r.env, '--apply'), '0 0\n');

  assert.deepEqual(r.tags('bill@x.test').filter((x) => x.startsWith('ledger/')), ['ledger/acme']);
  assert.deepEqual(r.files('HEY/PaperTrail'), ['bill.eml']);
});

test("a mail dragged into HEY/Bubbled comes back in a day, named by its thread's first Message-ID, unless a line already names the thread", (t) => {
  for (const known of [false, true]) {
    const r = heyRig(t);
    for (const s of ['new', 'cur', 'tmp']) mkdirSync(join(r.box('HEY/Bubbled'), s), { recursive: true });
    r.setDb('foldersync.db', 'HEY/Bubbled\n');
    r.arrive('INBOX', 'drag@x.test', 'drag.eml');
    r.notmuch('tag', '+screened', '--', 'id:drag@x.test');
    if (known) r.setDb('bubble.db', 'id:drag@x.test 4102444800\n');
    assert.equal(r.sync(r.env, '--apply'), '0 0\n');
    renameSync(join(r.box('INBOX'), 'new', 'drag.eml'), join(r.box('HEY/Bubbled'), 'new', 'drag.eml'));
    r.notmuch('new', '--quiet');
    const before = Math.floor(Date.now() / 1000);

    r.sync(r.env, '--apply');

    if (known) {
      assert.equal(r.db('bubble.db'), 'id:drag@x.test 4102444800\n');
      continue;
    }
    const [id, due] = r.db('bubble.db').trim().split(' ');
    assert.equal(id, 'id:drag@x.test');
    assert.ok(Number(due) >= before + 86400 && Number(due) <= before + 86460, due);
  }
});

test('a mail first seen in INBOX is still filed by its tags', (t) => {
  const r = heyRig(t);
  assert.equal(r.sync(r.env, '--apply'), '0 0\n');
  r.arrive('INBOX', 'tagged@x.test', 'tagged.eml');
  r.notmuch('tag', '+screened', '+replylater', '--', 'id:tagged@x.test');

  assert.equal(r.sync(r.env, '--apply'), '1 0\n');

  assert.deepEqual(r.files('HEY/ReplyLater'), ['tagged.eml']);
  assert.ok(r.tags('tagged@x.test').includes('replylater'));
});

// A pile on the phone takes the mail out of the Imbox as a pile here does, and moving it back to INBOX returns it.
test('a mail moved or first seen in HEY/ReplyLater or HEY/SetAside loses inbox, and one moved back to INBOX regains it', (t) => {
  const r = heyRig(t);
  for (const s of ['new', 'cur', 'tmp']) mkdirSync(join(r.box('HEY/SetAside'), s), { recursive: true });
  r.setDb('foldersync.db', 'HEY/ReplyLater\nHEY/SetAside\n');
  r.arrive('INBOX', 'moved@x.test', 'moved.eml');
  r.notmuch('tag', '+screened', '--', 'id:moved@x.test');
  assert.equal(r.sync(r.env, '--apply'), '0 0\n');
  renameSync(join(r.box('INBOX'), 'new', 'moved.eml'), join(r.box('HEY/ReplyLater'), 'new', 'moved.eml'));
  r.arrive('HEY/ReplyLater', 'later@x.test', 'later.eml');
  r.arrive('HEY/SetAside', 'aside@x.test', 'aside.eml');
  r.notmuch('tag', '+screened', '--', 'id:later@x.test or id:aside@x.test');
  r.sync(r.env, '--apply');
  for (const [id, pile] of [['moved@x.test', 'replylater'], ['later@x.test', 'replylater'], ['aside@x.test', 'setaside']]) {
    const tags = r.tags(id);
    assert.ok(tags.includes(pile) && !tags.includes('inbox'), `${id}: ${tags}`);
  }
  renameSync(join(r.box('HEY/ReplyLater'), 'new', 'moved.eml'), join(r.box('INBOX'), 'new', 'moved.eml'));
  r.notmuch('new', '--quiet');
  r.sync(r.env, '--apply');
  const back = r.tags('moved@x.test');
  assert.ok(back.includes('inbox') && !back.includes('replylater'), `back: ${back}`);
});
