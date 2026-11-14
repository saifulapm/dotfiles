// bin/mail seed on a scratch store (tests/home/mail-rig.mjs): it sorts the senders already in the store into HEY classes, and with no flag it changes nothing.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, mkdirSync, readdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { mailRig, repo } from './mail-rig.mjs';

const DAY = 86400e3;
const ago = (days) => new Date(Date.now() - days * DAY).toUTCString();

function rig(t) {
  const r = mailRig(t);
  let n = 0;
  // A mail in an iCloud folder other than INBOX; FLAGS is the maildir info, S for read.
  const put = (folder, headers, flags = '') => {
    for (const s of ['cur', 'new', 'tmp']) mkdirSync(join(r.mail, 'icloud', folder, s), { recursive: true });
    const text = Object.entries(headers).map(([k, v]) => `${k}: ${v}\n`).join('') + '\nhello\n';
    writeFileSync(join(r.mail, 'icloud', folder, 'cur', `seed${n++}:2,${flags}`), text);
    r.notmuch('new', '--quiet');
  };
  const seed = (...args) => r.run(join(repo, 'bin/mail'), ['seed', ...args]);
  const journal = join(r.env.XDG_STATE_HOME, 'hey-mail/decided');
  const snapshot = () => ({
    dump: r.notmuch('dump'),
    db: existsSync(r.env.HEY_MAIL_DB_DIR) ? readdirSync(r.env.HEY_MAIL_DB_DIR).sort().map((f) => [f, readFileSync(join(r.env.HEY_MAIL_DB_DIR, f), 'utf8')]) : null,
    journal: existsSync(journal) ? readFileSync(journal, 'utf8') : null,
  });
  const tags = (id) => r.notmuch('search', '--exclude=false', '--output=tags', '--', `id:${id}`).split('\n').filter(Boolean);
  return { ...r, put, seed, journal, snapshot, tags };
}

// One sender per class, each on a domain of its own, and a screened sender whose invoice would make it Paper Trail.
function store(t) {
  const r = rig(t);
  r.put('Sent Messages', { From: 'Me <me@x.test>', To: 'Bob <bob@people.test>', Subject: 'Re: plans', Date: ago(20), 'Message-ID': '<s1@x.test>' }, 'S');
  r.put('Sent Messages', { From: 'Me <me@x.test>', To: 'dave@quiet.test', Subject: 'hello', Date: ago(10), 'Message-ID': '<s2@x.test>' }, 'S');
  r.notmuch('tag', '+sent', '-inbox', '-unread', '--', 'folder:"icloud/Sent Messages"');
  r.deliver({ From: 'Bob <bob@people.test>', Subject: 'plans', Date: ago(21), 'Message-ID': '<b1@x.test>' });
  r.deliver({ From: 'CI <alerts@ci.test>', Subject: 'build failed', 'Auto-Submitted': 'auto-generated', Date: ago(3), 'Message-ID': '<a1@x.test>' });
  r.deliver({ From: 'Shop <noreply@shop.test>', Subject: 'Your receipt', 'List-Unsubscribe': '<mailto:u@shop.test>', Date: ago(4), 'Message-ID': '<r1@shop.test>' });
  r.deliver({ From: 'News <news@list.test>', Subject: 'weekly', 'List-Id': '<weekly.list.test>', Date: ago(5), 'Message-ID': '<n1@x.test>' });
  r.put('Junk', { From: 'Win <spam@junk.test>', To: 'me@x.test', Subject: 'you won', 'List-Unsubscribe': '<mailto:u@junk.test>', Date: ago(6), 'Message-ID': '<j1@x.test>' });
  r.deliver({ From: 'Carol <carol@far.test>', Subject: 'question', Date: ago(30), 'Message-ID': '<c1@x.test>' });
  r.deliver({ From: 'Old <old@stale.test>', Subject: 'long ago', Date: ago(395), 'Message-ID': '<o1@x.test>' });
  r.setDb('screened.db', 'zed@bills.test\n');
  r.deliver({ From: 'Zed <zed@bills.test>', Subject: 'Invoice 42', Date: ago(7), 'Message-ID': '<z1@x.test>' });
  return r;
}

const lines = (out) => out.split('\n');

test('mail seed counts every class, lists the lines it would write, and changes nothing', (t) => {
  const r = store(t);
  const before = r.snapshot();
  const res = r.seed();
  assert.equal(res.status, 0, res.stdout + res.stderr);
  const out = lines(res.stdout);
  for (const l of ['screened in: 2 senders, 3 messages', 'feed: 2 senders, 2 messages', 'paper trail: 1 senders, 1 messages',
    'junk only: 1 senders, 1 messages', 'screener: 1 senders, 1 messages', 'archived unclear: 1 senders, 1 messages', 'already decided: 1 senders',
    'screened.db me@x.test', 'screened.db bob@people.test', 'thefeed.db alerts@ci.test', 'thefeed.db news@list.test',
    'ledger.db receipts noreply@shop.test', 'screener carol@far.test', 'HEY/Read moves: 0']) {
    assert.ok(out.includes(l), `${l} in:\n${res.stdout}`);
  }
  assert.match(out[0], /dry run/);
  // A sender Saiful wrote to who never wrote back, a screened sender, the junk-only sender and the old one get no line.
  assert.doesNotMatch(res.stdout, /dave@quiet\.test|zed@bills\.test|spam@junk\.test|old@stale\.test|carol@far\.test \(|screened\.db carol/);
  assert.deepEqual(r.snapshot(), before);
});

test('mail seed gives a company three unclear senders one @domain line, and freemail one line each', (t) => {
  const r = rig(t);
  for (const who of ['a', 'b', 'c']) r.deliver({ From: `${who}@vendor.test`, Subject: 'hi', Date: ago(9), 'Message-ID': `<${who}@vendor.test>` });
  for (const who of ['x', 'y']) r.deliver({ From: `${who}@gmail.com`, Subject: 'hi', Date: ago(9), 'Message-ID': `<${who}@gmail.com>` });
  const res = r.seed();
  assert.equal(res.status, 0, res.stdout + res.stderr);
  const out = lines(res.stdout);
  assert.deepEqual(out.filter((l) => l.startsWith('screener ')), ['screener @vendor.test (3 senders)', 'screener x@gmail.com', 'screener y@gmail.com']);
  assert.ok(out.includes('screener: 5 senders, 5 messages'), res.stdout);
});

test('mail seed counts a HEY/Read mail of a sender it puts in The Feed as a move out of HEY/Read', (t) => {
  const r = rig(t);
  r.setDb('foldersync.db', 'HEY/Feed\n');
  r.put('HEY/Read', { From: 'News <news@list.test>', To: 'me@x.test', Subject: 'weekly', 'List-Id': '<weekly.list.test>', Date: ago(5), 'Message-ID': '<n1@x.test>' }, 'S');
  r.notmuch('tag', '+screened', '--', '*');
  const res = r.seed();
  assert.equal(res.status, 0, res.stdout + res.stderr);
  const out = lines(res.stdout);
  assert.ok(out.includes('  1  HEY/Read -> HEY/Feed'), res.stdout);
  assert.ok(out.includes('HEY/Read moves: 1'), res.stdout);
});

test('mail seed --apply writes each decision once and leaves unread as it was', (t) => {
  const r = store(t);
  const unread = r.notmuch('count', '--exclude=false', 'tag:unread');
  const zed = r.tags('z1@x.test');
  assert.ok(r.tags('r1@shop.test').includes('unread'));
  const res = r.seed('--apply');
  assert.equal(res.status, 0, res.stdout + res.stderr);
  assert.match(lines(res.stdout)[0], /applied/);
  assert.ok(r.tags('r1@shop.test').includes('ledger/receipts'));
  assert.equal(r.notmuch('count', '--exclude=false', 'tag:unread'), unread);
  assert.equal(r.db('ledger.db'), 'receipts noreply@shop.test\n');
  assert.equal(r.db('screened.db'), 'zed@bills.test\nme@x.test\nbob@people.test\n');
  assert.equal(r.db('thefeed.db'), 'alerts@ci.test\nnews@list.test\n');
  assert.deepEqual(r.tags('z1@x.test'), zed);
  const stamped = readFileSync(r.journal, 'utf8').trim().split('\n').map((l) => l.split(' ').slice(1).join(' ')).sort();
  assert.deepEqual(stamped, ['sender alerts@ci.test', 'sender bob@people.test', 'sender me@x.test', 'sender news@list.test', 'sender noreply@shop.test']);
  const before = r.snapshot();
  const again = r.seed('--apply');
  assert.equal(again.status, 0, again.stdout + again.stderr);
  assert.equal(again.stdout, 'nothing to change\n');
  assert.deepEqual(r.snapshot(), before);
});

test('mail seed counts a move hey-folder-sync would make for a mail with no From address too', (t) => {
  const r = rig(t);
  r.setDb('foldersync.db', 'HEY/Read\n');
  r.put('Archive', { To: 'me@x.test', Subject: 'no sender', Date: ago(5), 'Message-ID': '<nofrom@x.test>' }, 'S');
  r.notmuch('tag', '+screened', '+inbox', '--', 'id:nofrom@x.test');
  const res = r.seed();
  assert.equal(res.status, 0, res.stdout + res.stderr);
  assert.ok(lines(res.stdout).includes('  1  Archive -> HEY/Read'), res.stdout);
});

test('mail seed reads an Auto-Submitted value of raw 8-bit bytes', (t) => {
  const r = rig(t);
  r.put('INBOX', { From: 'bot@raw.test', To: 'me@x.test', Subject: 'hi', 'Auto-Submitted': 'auto-g\xe9n\xe9r\xe9', Date: ago(5), 'Message-ID': '<raw@x.test>' });
  const res = r.seed();
  assert.equal(res.status, 0, res.stdout + res.stderr);
  assert.ok(lines(res.stdout).includes('thefeed.db bot@raw.test'), res.stdout);
});
