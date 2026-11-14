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

test('a mail first seen in INBOX is still filed by its tags', (t) => {
  const r = heyRig(t);
  assert.equal(r.sync(r.env, '--apply'), '0 0\n');
  r.arrive('INBOX', 'tagged@x.test', 'tagged.eml');
  r.notmuch('tag', '+screened', '+replylater', '--', 'id:tagged@x.test');

  assert.equal(r.sync(r.env, '--apply'), '1 0\n');

  assert.deepEqual(r.files('HEY/ReplyLater'), ['tagged.eml']);
  assert.ok(r.tags('tagged@x.test').includes('replylater'));
});
