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
  const res = py(r, "E.refile('@vendor.test', 'screened', 'thefeed')");
  assert.equal(res.status, 0, res.stderr);
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

test("Kakoune's everything-from-this-sender list holds that address's mail alone", (t) => {
  const r = mailRig(t);
  ['Ann <ann@people.test>', 'x.ann@people.test', '"ann@people.test" <evil@bad.test>'].forEach((from, i) => r.deliver({ From: from, 'Message-ID': `<a${i}@x.test>` }));
  const res = r.kakMail('hey', 'sender', 'id:a0@x.test');
  assert.equal(res.status, 0, res.stderr);
  assert.deepEqual(r.notmuch('search', '--output=messages', '--', res.stdout.trim()).split('\n').filter(Boolean), ['id:a0@x.test']);
});

// An address's own line decides its mail over its domain's line, in either direction, as Saiful ruled.
const tagsOf = (r, id) => r.notmuch('search', '--exclude=false', '--output=tags', '--', `id:${id}`).split('\n').filter(Boolean).sort();
const py = (r, code) => r.run('python3', ['-B', '-c', `import mail_engine as E; ${code}`], { env: { ...r.env, PYTHONPATH: join(repo, 'bin') } });

test("post-new files an address with its own line by that line, not by its domain's", (t) => {
  const r = hooked(t);
  r.setDb('thefeed.db', '@vendor.test\nwebinars@mail.anthropic.test\n');
  r.setDb('screened.db', 'Boss@Vendor.test\n@mail.anthropic.test\n');
  r.setDb('ledger.db', 'receipts failed-payments@mail.anthropic.test\n');
  r.deliver({ From: 'boss@vendor.test', 'Message-ID': '<boss@x.test>' });
  r.deliver({ From: 'news@vendor.test', 'Message-ID': '<news@x.test>' });
  r.deliver({ From: 'webinars@mail.anthropic.test', 'Message-ID': '<web@x.test>' });
  r.deliver({ From: 'failed-payments@mail.anthropic.test', 'Message-ID': '<fail@x.test>' });
  r.deliver({ From: 'no-reply-xyz789@mail.anthropic.test', 'Message-ID': '<nr@x.test>' });
  assert.deepEqual(tagsOf(r, 'boss@x.test'), ['inbox', 'screened', 'unread']);
  assert.deepEqual(tagsOf(r, 'news@x.test'), ['archived', 'thefeed', 'unread']);
  assert.deepEqual(tagsOf(r, 'web@x.test'), ['archived', 'thefeed', 'unread']);
  assert.deepEqual(tagsOf(r, 'fail@x.test'), ['archived', 'ledger/receipts']);
  assert.deepEqual(tagsOf(r, 'nr@x.test'), ['inbox', 'screened', 'unread']);
});

test("a plain decision on an address under a domain line writes that address's line alone, which beats the domain's", (t) => {
  const r = hooked(t);
  r.setDb('screened.db', '@mail.anthropic.test\n');
  r.deliver({ From: 'news@mail.anthropic.test', 'Message-ID': '<news@x.test>' });
  r.deliver({ From: 'no-reply-abc123@mail.anthropic.test', 'Message-ID': '<nr1@x.test>' });
  const res = r.kakMail('hey', 'feed', 'id:news@x.test');
  assert.equal(res.stdout, 'feed: news@mail.anthropic.test\n', res.stderr);
  assert.equal(r.db('thefeed.db'), 'news@mail.anthropic.test\n');
  assert.equal(r.db('screened.db'), '@mail.anthropic.test\n');
  assert.deepEqual(tagsOf(r, 'news@x.test'), ['archived', 'thefeed', 'unread']);
  assert.deepEqual(tagsOf(r, 'nr1@x.test'), ['inbox', 'screened', 'unread']);
  r.deliver({ From: 'no-reply-xyz789@mail.anthropic.test', 'Message-ID': '<nr2@x.test>' });
  assert.deepEqual(tagsOf(r, 'nr2@x.test'), ['inbox', 'screened', 'unread']);
  // Unscreening the address drops its line, so its mail follows the domain's line again.
  assert.equal(r.kakMail('hey', 'unscreen', 'id:news@x.test').stdout, 'unscreen: news@mail.anthropic.test\n');
  assert.equal(r.db('thefeed.db'), '');
  // A stale archived tag beside inbox is m97's (the Feed-to-screened idea), so only the box tags are checked here.
  const news = tagsOf(r, 'news@x.test');
  assert.ok(news.includes('inbox') && news.includes('screened') && !news.includes('thefeed'), news.join(' '));
});

test("a domain's re-filing leaves alone every address with its own line, in either direction", (t) => {
  const r = mailRig(t);
  r.deliver({ From: 'boss@vendor.test', 'Message-ID': '<boss@x.test>' });
  r.deliver({ From: 'news@vendor.test', 'Message-ID': '<news@x.test>' });
  r.notmuch('tag', '-new', '--', '*');
  r.notmuch('tag', '+screened', '--', 'id:boss@x.test');
  r.setDb('screened.db', 'boss@vendor.test\n');
  const f = py(r, "E.refile('@vendor.test', None, 'thefeed')");
  assert.equal(f.status, 0, f.stderr);
  assert.deepEqual(tagsOf(r, 'boss@x.test'), ['inbox', 'screened', 'unread']);
  assert.deepEqual(tagsOf(r, 'news@x.test'), ['archived', 'thefeed', 'unread']);
  const u = py(r, "E.to_screener('@vendor.test')");
  assert.equal(u.status, 0, u.stderr);
  assert.deepEqual(tagsOf(r, 'boss@x.test'), ['inbox', 'screened', 'unread']);
  assert.deepEqual(tagsOf(r, 'news@x.test'), ['inbox', 'unread']);
});

// A domain decision: mail hey <screen-in|feed|papertrail> <id> --domain, and screen-out --sender @domain.
const mailCli = (r, ...args) => {
  const res = r.run(join(repo, 'bin/mail'), args);
  let json = null;
  try {
    json = JSON.parse(res.stdout);
  } catch {}
  return { ...res, json };
};
const dbFiles = (r) => ['screened.db', 'thefeed.db', 'spam.db', 'ledger.db'].map((f) => r.db(f));

test('mail hey screen-in --domain screens in every sender of that domain alone', (t) => {
  const r = hooked(t);
  r.deliver({ From: 'Anthropic <no-reply-abc123@mail.anthropic.test>', 'Message-ID': '<nr1@x.test>' });
  const res = mailCli(r, 'hey', 'screen-in', 'nr1@x.test', '--domain');
  assert.equal(res.status, 0, res.stdout + res.stderr);
  assert.equal(res.json.data.sender, '@mail.anthropic.test');
  assert.equal(r.db('screened.db'), '@mail.anthropic.test\n');
  assert.deepEqual(tagsOf(r, 'nr1@x.test'), ['inbox', 'screened', 'unread']);
  r.deliver({ From: 'no-reply-xyz789@mail.anthropic.test', 'Message-ID': '<nr2@x.test>' });
  r.deliver({ From: 'someone@anthropic.test', 'Message-ID': '<so@x.test>' });
  assert.deepEqual(tagsOf(r, 'nr2@x.test'), ['inbox', 'screened', 'unread']);
  assert.deepEqual(tagsOf(r, 'so@x.test'), ['inbox', 'unread']);
});

test('a domain decision on a freemail sender is refused and changes nothing', (t) => {
  const r = mailRig(t);
  r.deliver({ From: 'X <x@Gmail.com>', 'Message-ID': '<gm@x.test>' });
  r.setDb('screened.db', 'bob@people.test\n');
  const before = r.notmuch('dump');
  for (const action of ['screen-in', 'feed']) {
    const res = mailCli(r, 'hey', action, 'gm@x.test', '--domain');
    assert.equal(res.status, 1, res.stdout);
    assert.match(res.json.error, /gmail\.com is freemail/);
  }
  const p = mailCli(r, 'hey', 'papertrail', 'gm@x.test', '--domain', '--category', 'receipts');
  assert.equal(p.status, 1, p.stdout);
  const out = mailCli(r, 'hey', 'screen-out', '--sender', '@gmail.com');
  assert.equal(out.status, 1, out.stdout);
  assert.match(out.json.error, /gmail\.com is freemail/);
  assert.deepEqual(dbFiles(r), ['bob@people.test\n', '', '', '']);
  assert.equal(r.notmuch('dump'), before);
});

test('mail hey screen-out --sender @domain spams that domain, and --domain is only for the deciding actions', (t) => {
  const r = mailRig(t);
  r.deliver({ From: 'x@bad.test', 'Message-ID': '<b1@x.test>' });
  r.deliver({ From: 'y@sub.bad.test', 'Message-ID': '<b2@x.test>' });
  r.notmuch('tag', '-new', '--', '*');
  const res = mailCli(r, 'hey', 'screen-out', '--sender', '@Bad.test');
  assert.equal(res.status, 0, res.stdout + res.stderr);
  assert.equal(r.db('spam.db'), '@bad.test\n');
  assert.deepEqual(tagged(r, 'spam'), ['id:b1@x.test']);
  for (const args of [['screen-out', '--sender', '@test'], ['screen-out', '--sender', '@bad.test', '--domain'], ['archive', 'b2@x.test', '--domain']]) {
    const bad = mailCli(r, 'hey', ...args);
    assert.equal(bad.status, 1, `${args.join(' ')}: ${bad.stdout}`);
  }
  assert.equal(r.db('spam.db'), '@bad.test\n');
});

test("a domain decision leaves an address with its own line as it was, and so does unscreening the domain", (t) => {
  const r = hooked(t);
  r.setDb('screened.db', 'boss@vendor.test\n');
  r.deliver({ From: 'boss@vendor.test', 'Message-ID': '<boss@x.test>' });
  r.deliver({ From: 'news@vendor.test', 'Message-ID': '<news@x.test>' });
  const res = mailCli(r, 'hey', 'feed', 'news@x.test', '--domain');
  assert.equal(res.status, 0, res.stdout + res.stderr);
  assert.equal(r.db('thefeed.db'), '@vendor.test\n');
  assert.equal(r.db('screened.db'), 'boss@vendor.test\n');
  assert.deepEqual(tagsOf(r, 'boss@x.test'), ['inbox', 'screened', 'unread']);
  assert.deepEqual(tagsOf(r, 'news@x.test'), ['archived', 'thefeed', 'unread']);
  // Kakoune's unscreen on a sender only the domain line decides undoes that line.
  const u = r.kakMail('hey', 'unscreen', 'id:news@x.test');
  assert.equal(u.stdout, 'unscreen: @vendor.test\n', u.stderr);
  assert.equal(r.db('thefeed.db'), '');
  assert.deepEqual(tagsOf(r, 'news@x.test'), ['inbox', 'unread']);
  assert.deepEqual(tagsOf(r, 'boss@x.test'), ['inbox', 'screened', 'unread']);
});

test('kak-mail hey --domain takes the domain of each selected sender', (t) => {
  const r = mailRig(t);
  r.deliver({ From: 'no-reply-abc123@mail.anthropic.test', 'Message-ID': '<nr1@x.test>' });
  r.deliver({ From: 'x@bad.test', 'Message-ID': '<b1@x.test>' });
  r.notmuch('tag', '-new', '--', '*');
  assert.equal(r.kakMail('hey', 'screen-in', '--domain', 'id:nr1@x.test').stdout, 'screen-in: @mail.anthropic.test\n');
  assert.equal(r.kakMail('hey', 'screen-out', '--domain', 'id:b1@x.test').stdout, 'screen-out: @bad.test\n');
  assert.equal(r.kakMail('hey', 'papertrail', '--arg', 'receipts', '--domain', 'id:nr1@x.test').stdout, 'papertrail: @mail.anthropic.test\n');
  assert.equal(r.db('screened.db'), '');
  assert.equal(r.db('ledger.db'), 'receipts @mail.anthropic.test\n');
  assert.equal(r.db('spam.db'), '@bad.test\n');
});

// A From header holding two addresses is decided by its last one, by its own line or its domain's, however the list is spelled.
test("an address with its own line is decided by that line when it ends a From header's list, in either spelling", (t) => {
  const r = hooked(t);
  r.setDb('thefeed.db', '@vendor.test\n');
  r.setDb('screened.db', 'boss@vendor.test\n');
  r.deliver({ From: 'evil@bad.test, boss@vendor.test', 'Message-ID': '<l1@x.test>' });
  r.deliver({ From: 'Evil <e@bad.test>, <boss@vendor.test>', 'Message-ID': '<l2@x.test>' });
  r.deliver({ From: 'boss@vendor.test, evil@bad.test', 'Message-ID': '<l3@x.test>' });
  assert.deepEqual(tagsOf(r, 'l1@x.test'), ['inbox', 'screened', 'unread']);
  assert.deepEqual(tagsOf(r, 'l2@x.test'), ['inbox', 'screened', 'unread']);
  assert.deepEqual(tagsOf(r, 'l3@x.test'), ['inbox', 'unread']);
});

test('a refused domain decision says what to do instead, not that notmuch failed', (t) => {
  const r = mailRig(t);
  r.deliver({ From: 'x@gmail.com', 'Message-ID': '<gm@x.test>' });
  for (const args of [['screen-in', 'gm@x.test', '--domain'], ['screen-out', '--sender', '@gmail.com'], ['screen-out', '--sender', '@test']]) {
    const res = mailCli(r, 'hey', ...args);
    assert.equal(res.status, 1, res.stdout);
    assert.doesNotMatch(res.json.hint, /notmuch failed/, args.join(' '));
  }
  assert.match(mailCli(r, 'hey', 'screen-in', 'gm@x.test', '--domain').json.hint, /without --domain/);
  assert.match(mailCli(r, 'hey', 'screen-out', '--sender', '@test').json.hint, /dot/);
});
