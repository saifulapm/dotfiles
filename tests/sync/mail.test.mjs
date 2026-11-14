// Two machines, a and b, carry HEY decisions through dots sync's mail unit, each with its own scratch notmuch store.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { deliver, kakMail, machine, mailbox, notmuch, sync, world } from './lib.mjs';

const db = (m, name) => (existsSync(join(m.hey, name)) ? readFileSync(join(m.hey, name), 'utf8') : '');
const remote = (w, id) => join(w.remote, 'dots-sync/mail', id + '.json');

async function ok(m, args) {
  const r = await sync(m, args);
  assert.equal(r.code, 0, `dots sync on ${m.id} exited ${r.code}: ${r.stdout}${r.stderr}`);
  return r;
}

// Two machines with mail, each started once, since a full round leaves a machine's mail alone until then.
async function pair() {
  const w = world();
  const [a, b] = [machine(w, 'a'), machine(w, 'b')];
  for (const m of [a, b]) {
    await mailbox(m);
    await ok(m, ['--only', 'mail']);
  }
  return { w, a, b };
}

async function hey(m, action, id) {
  const r = await kakMail(m, ['hey', action, 'id:' + id]);
  assert.equal(r.code, 0, r.stderr);
}

const count = async (m, q) => Number((await notmuch(m, ['count', q])).stdout.trim());

test('a full round leaves mail alone on a machine not started, and --only mail starts it', async () => {
  const w = world();
  const a = machine(w, 'a');
  await mailbox(a);
  writeFileSync(join(a.hey, 'screened.db'), 'x@y.test\n');
  const r = await ok(a);
  assert.match(r.stdout, /^dots sync: mail skipped, not started here; dots sync --only mail starts it$/m);
  assert.equal(existsSync(remote(w, 'a')), false);
  await ok(a, ['--only', 'mail']);
  assert.ok(existsSync(remote(w, 'a')));
  // Once started, the full round carries mail too.
  writeFileSync(join(a.hey, 'screened.db'), 'x@y.test\nz@y.test\n');
  await ok(a);
  assert.match(readFileSync(remote(w, 'a'), 'utf8'), /z@y\.test/);
});

test('a sender screened in on a reaches b, and b files its older mail from it as screened', async () => {
  const { a, b } = await pair();
  await deliver(a, 'X <x@y.test>', 'a1@y.test');
  for (const n of [1, 2, 3]) await deliver(b, 'X <x@y.test>', `b${n}@y.test`);
  await hey(a, 'screen-in', 'a1@y.test');
  await ok(a);
  await ok(b);
  assert.match(db(b, 'screened.db'), /^x@y\.test$/m);
  assert.equal(await count(b, 'from:x@y.test and tag:screened'), 3);
});

test('a sender unscreened on b is gone from a after b then a sync', async () => {
  const { a, b } = await pair();
  await deliver(a, 'x@y.test', 'a1@y.test');
  await deliver(b, 'x@y.test', 'b1@y.test');
  await hey(a, 'screen-in', 'a1@y.test');
  await ok(a);
  await ok(b);
  await hey(b, 'unscreen', 'b1@y.test');
  await ok(b);
  await ok(a);
  assert.doesNotMatch(db(a, 'screened.db'), /x@y\.test/);
  assert.equal(await count(a, 'tag:screened'), 0);
});

// b syncs first, so a stamp taken at sync time would hand the win to a's earlier decision.
test('a sender a moved to The Feed and b later screened in ends screened in on both, wherever the syncs fall', async () => {
  const { a, b } = await pair();
  await deliver(a, 'z@y.test', 'a1@y.test');
  await deliver(b, 'z@y.test', 'b1@y.test');
  await hey(a, 'feed', 'a1@y.test');
  await new Promise((done) => setTimeout(done, 20));
  await hey(b, 'screen-in', 'b1@y.test');
  for (const m of [b, a, b, a]) await ok(m);
  for (const m of [a, b]) {
    assert.match(db(m, 'screened.db'), /^z@y\.test$/m, m.id);
    assert.doesNotMatch(db(m, 'thefeed.db'), /z@y\.test/, m.id);
  }
  assert.equal(await count(a, 'tag:thefeed'), 0);
  assert.equal(await count(a, 'tag:screened'), 1);
});

// b decides after it has seen a's decision, with a clock a minute behind a's.
test("a decision made after another machine's still wins when its clock runs a minute slow", async () => {
  const { a, b } = await pair();
  await deliver(a, 'z@y.test', 'a1@y.test');
  await deliver(b, 'z@y.test', 'b1@y.test');
  await hey(a, 'screen-in', 'a1@y.test');
  await ok(a);
  await ok(b);
  const journal = join(b.env.XDG_STATE_HOME, 'hey-mail/decided');
  await hey(b, 'feed', 'b1@y.test');
  writeFileSync(journal, readFileSync(journal, 'utf8').replace(/^\d+/gm, (t) => String(Number(t) - 60000)));
  await ok(b);
  await ok(a);
  assert.match(db(a, 'thefeed.db'), /^z@y\.test$/m);
  assert.doesNotMatch(db(a, 'screened.db'), /z@y\.test/);
});

test("another machine's mail file that does not parse fails the unit with 5 and leaves the local files as they were", async () => {
  const { w, b } = await pair();
  writeFileSync(join(b.hey, 'screened.db'), 'x@y.test\n');
  writeFileSync(join(b.hey, 'foldersync.db'), '# boxes\nHEY/Feed\n');
  await ok(b);
  const before = ['screened.db', 'foldersync.db'].map((f) => db(b, f));
  writeFileSync(remote(w, 'a'), '{"v":1,"records":');
  const r = await sync(b, ['--only', 'mail']);
  assert.equal(r.code, 5, r.stdout + r.stderr);
  assert.match(r.stderr, /^dots sync: mail: skipped a\.json, which does not parse$/m);
  assert.deepEqual(['screened.db', 'foldersync.db'].map((f) => db(b, f)), before);
});

test('the boxes enabled on either machine end enabled on both, each keeping its own header', async () => {
  const { a, b } = await pair();
  writeFileSync(join(a.hey, 'foldersync.db'), '# a header\nHEY/Feed\nHEY/ReplyLater\n');
  writeFileSync(join(b.hey, 'foldersync.db'), '# b header\nHEY/Read\n');
  await ok(a);
  await ok(b);
  await ok(a);
  assert.equal(db(a, 'foldersync.db'), '# a header\nHEY/Feed\nHEY/ReplyLater\nHEY/Read\n');
  assert.equal(db(b, 'foldersync.db'), '# b header\nHEY/Read\nHEY/Feed\nHEY/ReplyLater\n');
});

test("the away message and its replied list stay on a's machine", async () => {
  const { w, a, b } = await pair();
  writeFileSync(join(a.hey, 'away'), 'until: 2099-01-01\n\nback soon\n');
  writeFileSync(join(a.hey, 'away-replied.db'), 'x@y.test\n');
  writeFileSync(join(a.hey, 'screened.db'), 'x@y.test\n');
  await ok(a);
  await ok(b);
  assert.equal(existsSync(join(b.hey, 'away')), false);
  assert.equal(existsSync(join(b.hey, 'away-replied.db')), false);
  assert.doesNotMatch(readFileSync(remote(w, 'a'), 'utf8'), /away|back soon/);
});

test('a pulled record naming a sender notmuch would read as a query is left out, and the unit says so', async () => {
  const { w, b } = await pair();
  mkdirSync(dirname(remote(w, 'a')), { recursive: true });
  const at = Date.now();
  // notmuch reads from:/re/ as a regex over every sender, and a list value is no class.
  const records = {
    'sender *': { v: 'screened', at },
    'sender a@b.test or tag:inbox': { v: 'spam', at },
    'sender /.+@.+/': { v: 'spam', at },
    'sender l@y.test': { v: ['screened'], at },
    'mute id:m@y.test': { v: { x: 1 }, at },
    // A regex code, a top-level domain and a zero-day recycle each match every mail post-new sees.
    speakeasy: { v: '/./', at },
    'sender @test': { v: 'spam', at },
    'recycle ok@y.test': { v: '0', at },
    'sender ok@y.test': { v: 'screened', at },
  };
  writeFileSync(remote(w, 'a'), JSON.stringify({ v: 1, records }));
  const r = await sync(b, ['--only', 'mail']);
  assert.equal(r.code, 5, r.stdout + r.stderr);
  assert.match(r.stderr, /^dots sync: mail: left out 8 records from a\.json, which are not HEY decisions$/m);
  assert.equal(db(b, 'screened.db'), 'ok@y.test\n');
  assert.equal(db(b, 'spam.db'), '');
});

test("autofile, notify, recycle and speakeasy travel with the sender's label, and so do their removals", async () => {
  const { a, b } = await pair();
  await deliver(a, 'x@y.test', 'a1@y.test');
  await deliver(b, 'x@y.test', 'b1@y.test');
  // A longer address ending in the sender's is another sender.
  await deliver(b, 'x.x@y.test', 'b2@y.test');
  for (const [action, arg] of [['autofile', 'Work'], ['recycle', '30']]) {
    const r = await kakMail(a, ['hey', action, '--arg', arg, 'id:a1@y.test']);
    assert.equal(r.code, 0, r.stderr);
  }
  writeFileSync(join(a.hey, 'notify.db'), 'x@y.test\n');
  writeFileSync(join(a.hey, 'speakeasy'), 'open-sesame\n');
  await ok(a);
  await ok(b);
  assert.deepEqual(['autofile.db', 'recycle.db', 'notify.db', 'speakeasy'].map((f) => db(b, f)), ['x@y.test Work\n', 'x@y.test 30\n', 'x@y.test\n', 'open-sesame\n']);
  assert.equal(await count(b, 'tag:label/Work'), 1);

  const r = await kakMail(a, ['hey', 'unscreen', 'id:a1@y.test']);
  assert.equal(r.code, 0, r.stderr);
  writeFileSync(join(a.hey, 'notify.db'), '');
  writeFileSync(join(a.hey, 'speakeasy'), '');
  await ok(a);
  await ok(b);
  assert.deepEqual(['autofile.db', 'recycle.db', 'notify.db', 'speakeasy'].map((f) => db(b, f)), ['', '', '', '']);
  assert.equal(await count(b, 'tag:label/Work'), 0);
});

const bubbles = (m) => db(m, 'bubble.db');
const tags = async (m, id) => (await notmuch(m, ['search', '--exclude=false', '--output=tags', 'id:' + id])).stdout.trim().split('\n');

test("a bubble.db line keyed by a thread id becomes its thread's first Message-ID once, keeping its due time", async () => {
  const { b } = await pair();
  await deliver(b, 'x@y.test', 'first@y.test');
  await deliver(b, 'x@y.test', 'second@y.test', 'first@y.test');
  const tid = (await notmuch(b, ['search', '--output=threads', 'id:second@y.test'])).stdout.trim().replace(/^thread:/, '');
  writeFileSync(join(b.hey, 'bubble.db'), `${tid} 4102444800\n`);
  await ok(b, ['--only', 'mail']);
  assert.equal(bubbles(b), 'id:first@y.test 4102444800\n');
  await ok(b, ['--only', 'mail']);
  assert.equal(bubbles(b), 'id:first@y.test 4102444800\n');
});

test('a bubble set on a comes up on b once its time passed, after a sync and one mail sync', async () => {
  const w = world();
  const [a, b] = [machine(w, 'a'), machine(w, 'b')];
  await mailbox(a);
  await mailbox(b, { hooks: true });
  for (const m of [a, b]) await ok(m, ['--only', 'mail']);
  await deliver(a, 'x@y.test', 'b1@x.test');
  await deliver(b, 'x@y.test', 'b1@x.test');
  await notmuch(b, ['tag', '-unread', '-inbox', '--', 'id:b1@x.test']);
  const r = await kakMail(a, ['hey', 'bubble', '--arg', '2 seconds', 'id:b1@x.test']);
  assert.equal(r.code, 0, r.stderr);
  await ok(a);
  await new Promise((done) => setTimeout(done, 2500));
  await ok(b);
  assert.match(bubbles(b), /^id:b1@x\.test \d+$/m);
  await notmuch(b, ['new', '--quiet']);
  const got = await tags(b, 'b1@x.test');
  for (const t of ['bubbled', 'inbox', 'unread']) assert.ok(got.includes(t), `${t} in ${got}`);
  assert.ok(!got.includes('bubble'), got.join(' '));
  assert.equal(bubbles(b), '');
  // b's fired bubble is not set again by a's line, which a's own mail sync has yet to fire.
  await ok(b);
  await ok(a);
  await ok(b);
  assert.equal(bubbles(b), '');
});

// hey-folder-sync writes a day's default for a mail dragged into HEY/Bubbled before the bubble's record arrives.
test("a bubble's real due on a outvotes the default b wrote for the same thread", async () => {
  const { a, b } = await pair();
  await deliver(a, 'x@y.test', 'b1@x.test');
  await deliver(b, 'x@y.test', 'b1@x.test');
  const r = await kakMail(a, ['hey', 'bubble', '--arg', '2099-01-01 09:00', 'id:b1@x.test']);
  assert.equal(r.code, 0, r.stderr);
  const due = bubbles(a);
  assert.match(due, /^id:b1@x\.test \d+\n$/);
  await ok(a);
  writeFileSync(join(b.hey, 'bubble.db'), `id:b1@x.test ${Math.floor(Date.now() / 1000) + 86400}\n`);
  await ok(b);
  await ok(a);
  assert.equal(bubbles(b), due);
  assert.equal(bubbles(a), due);
});

test("a mute on a's machine mutes the thread on b, keeps b's new mail in it muted, and an unmute travels too", async () => {
  const w = world();
  const [a, b] = [machine(w, 'a'), machine(w, 'b')];
  await mailbox(a);
  await mailbox(b, { hooks: true });
  for (const m of [a, b]) await ok(m, ['--only', 'mail']);
  await deliver(b, 'x@y.test', 'm1@x.test');
  await deliver(b, 'x@y.test', 'm2@x.test', 'm1@x.test');
  writeFileSync(join(a.hey, 'muted.db'), 'id:m1@x.test\nid:m9@x.test\n');
  await ok(a);
  await ok(b);
  assert.equal(db(b, 'muted.db'), 'id:m1@x.test\nid:m9@x.test\n');
  assert.equal(await count(b, 'tag:muted and not tag:inbox'), 2);
  await deliver(b, 'x@y.test', 'm3@x.test', 'm2@x.test');
  assert.ok((await tags(b, 'm3@x.test')).includes('muted'));
  // The record came before any mail of that thread did.
  await deliver(b, 'x@y.test', 'm9@x.test');
  assert.ok((await tags(b, 'm9@x.test')).includes('muted'));
  writeFileSync(join(a.hey, 'muted.db'), '');
  await ok(a);
  await ok(b);
  assert.equal(db(b, 'muted.db'), '');
  assert.equal(await count(b, 'tag:muted'), 0);
});

// a's unscreen and b's screen-in again both change nothing b's files hold, yet b decided last.
test('a sender screened in again after another machine unscreened it ends screened in', async () => {
  const { a, b } = await pair();
  await deliver(a, 'x@y.test', 'a1@y.test');
  await deliver(b, 'x@y.test', 'b1@y.test');
  await hey(a, 'screen-in', 'a1@y.test');
  await ok(a);
  await ok(b);
  await hey(a, 'unscreen', 'a1@y.test');
  await new Promise((done) => setTimeout(done, 20));
  await hey(b, 'screen-in', 'b1@y.test');
  for (const m of [a, b, a]) await ok(m);
  for (const m of [a, b]) assert.match(db(m, 'screened.db'), /^x@y\.test$/m, m.id);
});

// a's store lacks the thread's older mail, so a and b name one thread by different Message-IDs.
test("a bubble on a thread retires b's older bubble line for the same thread under another Message-ID", async () => {
  const { a, b } = await pair();
  await deliver(a, 'x@y.test', 'new@y.test', 'old@y.test');
  await deliver(b, 'x@y.test', 'old@y.test');
  await deliver(b, 'x@y.test', 'new@y.test', 'old@y.test');
  writeFileSync(join(b.hey, 'bubble.db'), `id:old@y.test ${Math.floor(Date.now() / 1000) + 86400}\n`);
  await ok(b);
  const r = await kakMail(a, ['hey', 'bubble', '--arg', '2099-01-01 09:00', 'id:new@y.test']);
  assert.equal(r.code, 0, r.stderr);
  const due = bubbles(a);
  assert.match(due, /^id:new@y\.test \d+\n$/);
  for (const m of [a, b, a, b]) await ok(m);
  assert.equal(bubbles(b), due);
  assert.equal(bubbles(a), due);
});

test('a pulled decision whose re-filing failed is re-filed by the next round', async () => {
  const { a, b } = await pair();
  await deliver(a, 'x@y.test', 'a1@y.test');
  await deliver(b, 'x@y.test', 'b1@y.test');
  await hey(a, 'screen-out', 'a1@y.test');
  await ok(a);
  const stub = join(b.env.HOME, 'failing');
  mkdirSync(stub);
  writeFileSync(join(stub, 'notmuch'), '#!/bin/sh\n[ "$1" = tag ] && exit 1\nexec /usr/bin/notmuch "$@"\n', { mode: 0o755 });
  const path = b.env.PATH;
  b.env.PATH = stub + ':' + path;
  const r = await sync(b);
  assert.equal(r.code, 1, r.stdout + r.stderr);
  b.env.PATH = path;
  await ok(b);
  assert.match(db(b, 'spam.db'), /^x@y\.test$/m);
  assert.equal(await count(b, 'tag:spam and from:x@y.test'), 1);
});

// The journal names the key, the store holds its removal, and the line fired before this round looked.
test('a bubble set and fired again between two rounds leaves the round green', async () => {
  const w = world();
  const b = machine(w, 'b');
  await mailbox(b, { hooks: true });
  await ok(b, ['--only', 'mail']);
  await deliver(b, 'x@y.test', 'b1@x.test');
  for (let i = 0; i < 2; i++) {
    const r = await kakMail(b, ['hey', 'bubble', '--arg', '2 seconds', 'id:b1@x.test']);
    assert.equal(r.code, 0, r.stderr);
    if (i === 0) await ok(b);
    await new Promise((done) => setTimeout(done, 2500));
    await notmuch(b, ['new', '--quiet']);
    await ok(b);
  }
  await ok(b);
  assert.equal(bubbles(b), '');
});

// The first sync took the union of three machines' files, which left some senders with a line in two class files.
test("a round drops a sender's line from each class file its decision does not name", async () => {
  const { a } = await pair();
  writeFileSync(join(a.hey, 'screened.db'), 'x@y.test\nkeep@y.test\n');
  writeFileSync(join(a.hey, 'spam.db'), 'x@y.test\n');
  await ok(a, ['--only', 'mail']);
  assert.equal(db(a, 'screened.db'), 'keep@y.test\n');
  assert.equal(db(a, 'spam.db'), 'x@y.test\n');
  await ok(a, ['--only', 'mail']);
  assert.equal(db(a, 'screened.db'), 'keep@y.test\n');
});
