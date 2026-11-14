// What a sender key in the HEY db files matches, through post-new and the engine: notmuch reads from:"@vendor.test" as a phrase, which also matches a subdomain, another domain ending in it, and a display name.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { chmodSync, copyFileSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { mailRig, repo } from './mail-rig.mjs';

// The rig, with post-new run by notmuch new.
function hooked(t) {
  const r = mailRig(t);
  const hooks = join(r.M, 'hooks');
  mkdirSync(hooks);
  copyFileSync(join(repo, 'home/dot_config/notmuch/hooks/executable_post-new'), join(hooks, 'post-new'));
  chmodSync(join(hooks, 'post-new'), 0o755);
  const cfg = join(r.M, 'notmuch-config');
  writeFileSync(cfg, readFileSync(cfg, 'utf8').replace('[database]\n', `[database]\nhook_dir=${hooks}\n`));
  return r;
}

const senders = ['A <a@vendor.test>', 'D@Vendor.Test', 'b@mail.vendor.test', '"Vendor Test" <e@other.com>', 'c@vendor.test.evil.com'];
const deliverAll = (r) => senders.forEach((from, i) => r.deliver({ From: from, 'Message-ID': `<v${i}@x.test>` }));
const tagged = (r, tag) => r.notmuch('search', '--exclude=false', '--output=messages', '--', `tag:${tag}`).split('\n').filter(Boolean).sort();

test('post-new files new mail by an @domain line for that domain alone, in any case', (t) => {
  const r = hooked(t);
  r.setDb('screened.db', '@vendor.test\n');
  r.setDb('ledger.db', 'receipts @vendor.test\n');
  deliverAll(r);
  assert.deepEqual(tagged(r, 'screened'), ['id:v0@x.test', 'id:v1@x.test']);
  assert.deepEqual(tagged(r, 'ledger/receipts'), ['id:v0@x.test', 'id:v1@x.test']);
});

test('a decision on an @domain line re-files that domain alone', (t) => {
  const r = mailRig(t);
  deliverAll(r);
  r.notmuch('tag', '-new', '--', '*');
  r.setDb('screened.db', '@vendor.test\n');
  const res = r.kakMail('hey', 'feed', 'id:v0@x.test');
  assert.equal(res.stdout, 'feed: @vendor.test\n', res.stderr);
  assert.deepEqual(tagged(r, 'thefeed'), ['id:v0@x.test', 'id:v1@x.test']);
});

test('a decision on a sender with no local part is refused, as its line would match a whole domain', (t) => {
  const r = mailRig(t);
  const py = r.run('python3', ['-B', '-c', "import mail_engine as E; E.decide('screen-in', '@gmail.com')"], { env: { ...r.env, PYTHONPATH: join(repo, 'bin') } });
  assert.notEqual(py.status, 0);
  assert.match(py.stderr, /not one plain address/);
  assert.equal(r.db('screened.db'), '');
});

// The machine that unscreened marks the mail unread, and iCloud carries the flag to the others.
test('an unscreen another machine made re-files the mail here without marking it unread', (t) => {
  const r = mailRig(t);
  r.deliver({ From: 'news@shop.test', Date: new Date(Date.now() - 5 * 86400e3).toUTCString(), 'Message-ID': '<s@x.test>' });
  r.notmuch('tag', '-new', '-unread', '+thefeed', '+archived', '-inbox', '--', '*');
  const py = r.run('python3', ['-B', '-c', "import mail_engine as E; E.refile('news@shop.test', 'thefeed', None)"], { env: { ...r.env, PYTHONPATH: join(repo, 'bin') } });
  assert.equal(py.status, 0, py.stderr);
  assert.deepEqual(r.notmuch('search', '--output=tags', '--', 'id:s@x.test').split('\n').filter(Boolean), ['inbox']);
});

// An address line is the From address exactly, in any case: notmuch reads from:"noreply@google.com" as a phrase, which also matches googlebase-noreply@google.com and a stranger whose display name spells it.
const spoofs = ['Google <NoReply@Google.com>', 'googlebase-noreply@google.com', '"noreply@google.com" <evil@bad.test>', 'Store <store+97131659547@g.shopifyemail.com>', 'my-store+97131659547@g.shopifyemail.com', 'bare-noreply@google.com'];
const deliverSpoofs = (r) => spoofs.forEach((from, i) => r.deliver({ From: from, 'Message-ID': `<g${i}@x.test>` }));

test('post-new files new mail by an address line for that address alone, in any case', (t) => {
  const r = hooked(t);
  r.setDb('screened.db', 'noreply@google.com\nbare-noreply@google.com\n');
  r.setDb('ledger.db', 'receipts store+97131659547@g.shopifyemail.com\n');
  r.setDb('autofile.db', 'noreply@google.com google\n');
  deliverSpoofs(r);
  assert.deepEqual(tagged(r, 'screened'), ['id:g0@x.test', 'id:g5@x.test']);
  assert.deepEqual(tagged(r, 'ledger/receipts'), ['id:g3@x.test']);
  assert.deepEqual(tagged(r, 'label/google'), ['id:g0@x.test']);
});

test('post-new leaves out a line that is neither one address nor an @domain', (t) => {
  const r = hooked(t);
  r.setDb('screened.db', '/.+@.+/\n@test\nann@people.test\n');
  deliverSpoofs(r);
  r.deliver({ From: 'Ann <ann@people.test>', 'Message-ID': '<ann@x.test>' });
  assert.deepEqual(tagged(r, 'screened'), ['id:ann@x.test']);
});

test('a decision on an address re-files that address alone, in any case', (t) => {
  const r = mailRig(t);
  deliverSpoofs(r);
  r.notmuch('tag', '-new', '--', '*');
  const res = r.kakMail('hey', 'screen-in', 'id:g0@x.test');
  assert.equal(res.stdout, 'screen-in: noreply@google.com\n', res.stderr);
  assert.deepEqual(tagged(r, 'screened'), ['id:g0@x.test']);
  assert.equal(r.kakMail('hey', 'papertrail', '--arg', 'receipts', 'id:g3@x.test').status, 0);
  assert.deepEqual(tagged(r, 'ledger/receipts'), ['id:g3@x.test']);
});

test('mail hey screen-out --sender spams that address alone', (t) => {
  const r = mailRig(t);
  ['Ann <ann@people.test>', 'x.ann@people.test', 'ann@people.test.uk'].forEach((from, i) => r.deliver({ From: from, 'Message-ID': `<a${i}@x.test>` }));
  r.notmuch('tag', '-new', '--', '*');
  const res = r.run(join(repo, 'bin/mail'), ['hey', 'screen-out', '--sender', 'ann@people.test']);
  assert.equal(res.status, 0, res.stderr);
  assert.deepEqual(tagged(r, 'spam'), ['id:a0@x.test']);
});
