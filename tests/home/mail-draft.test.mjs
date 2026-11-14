// bin/mail's drafts on a scratch store (tests/home/mail-rig.mjs): an agent writes drafts where Kakoune keeps them, and draft show prints what would go out with a digest of it.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { mailRig, me, repo } from './mail-rig.mjs';

const OPEN = '<<<untrusted-mail>>>';
const CLOSE = '<<<end-untrusted-mail>>>';
const wrapped = (s) => `${OPEN}${s}${CLOSE}`;

function rig(t, { aliases = [] } = {}) {
  const r = mailRig(t);
  if (aliases.length) writeFileSync(r.env.NOTMUCH_CONFIG, readFileSync(r.env.NOTMUCH_CONFIG, 'utf8').replace('primary_email=', `other_email=${aliases.join(';')}\nprimary_email=`));
  const mail = (...args) => {
    const res = r.run(join(repo, 'bin/mail'), args);
    let json = null;
    try {
      json = JSON.parse(res.stdout);
    } catch {}
    return { ...res, json };
  };
  const file = (name, text) => {
    const p = join(r.M, name);
    writeFileSync(p, text);
    return p;
  };
  const drafts = join(r.env.XDG_DATA_HOME, 'kak-mail/drafts');
  return { ...r, mail, file, drafts };
}

test('mail draft new writes a draft where Kakoune keeps them, from the primary address', (t) => {
  const r = rig(t);
  const res = r.mail('draft', 'new', '--to', 'ann@people.test', '--subject', 'Hi', '--body-file', r.file('b.txt', 'hello Ann\n'));
  assert.equal(res.status, 0, res.stdout + res.stderr);
  assert.match(res.stdout, /^\{"ok":true,"data":\{"id":"[^"]+","path":"[^"]+\/kak-mail\/drafts\/[^"]+\.eml"\}\}\n$/);
  const { id, path } = res.json.data;
  assert.equal(path, join(r.drafts, `${id}.eml`));
  assert.equal(readFileSync(path, 'utf8'), `From: Me <${me}>\nTo: ann@people.test\nSubject: Hi\n\nhello Ann\n\n`);
});

test('a draft body file with CRLF line ends is written with LF', (t) => {
  const r = rig(t);
  const res = r.mail('draft', 'new', '--to', 'ann@people.test, bob@people.test', '--subject', 'Hi', '--body-file', r.file('b.txt', 'one\r\ntwo\r\n'));
  assert.equal(res.status, 0, res.stdout + res.stderr);
  const shown = r.mail('draft', 'show', res.json.data.id).json.data;
  assert.equal(shown.body, wrapped('one\ntwo'));
  assert.deepEqual(shown.to.map((p) => p.address), ['ann@people.test', 'bob@people.test']);
});

test('mail draft new --from takes only one of your addresses', (t) => {
  const r = rig(t, { aliases: ['alias2@x.test'] });
  const bad = r.mail('draft', 'new', '--to', 'ann@people.test', '--from', 'x@nope.test');
  assert.equal(bad.status, 1, bad.stdout);
  assert.equal(bad.json.ok, false);
  assert.equal(bad.json.error, 'x@nope.test is not one of your addresses');
  assert.ok(!existsSync(r.drafts) || readdirSync(r.drafts).length === 0, 'no draft written');
  const good = r.mail('draft', 'new', '--to', 'ann@people.test', '--from', 'ALIAS2@x.test');
  assert.equal(good.status, 0, good.stdout);
  assert.match(readFileSync(good.json.data.path, 'utf8'), /^From: Me <alias2@x\.test>\n/);
});

test('mail draft reply goes from the alias the mail was sent to, and from the primary for an address that is not yours', (t) => {
  const r = rig(t, { aliases: ['alias2@x.test'] });
  r.deliver({ To: 'alias2@x.test', Subject: 'to the alias', 'Message-ID': '<a1@x.test>' });
  r.deliver({ To: 'stranger@x.test', Subject: 'to someone else', 'Message-ID': '<a2@x.test>' });
  const toAlias = r.mail('draft', 'reply', 'a1@x.test', '--body-file', r.file('b.txt', 'thanks\n'));
  assert.equal(toAlias.status, 0, toAlias.stdout);
  const text = readFileSync(toAlias.json.data.path, 'utf8');
  assert.match(text, /^From: Me <alias2@x\.test>\n/);
  assert.match(text, /\nTo: Ann <ann@people\.test>\n/);
  assert.match(text, /\nIn-Reply-To: <a1@x\.test>\n/);
  // The agent's words come first, then the quote.
  assert.match(text, /\n\nthanks\n\nOn .*Ann <ann@people\.test> wrote:\n> hello\n/);
  const other = r.mail('draft', 'reply', 'a2@x.test');
  assert.match(readFileSync(other.json.data.path, 'utf8'), new RegExp(`^From: Me <${me}>\\n`));
});

test('mail draft forward and replyall take the message id, and an unknown id is not found', (t) => {
  const r = rig(t);
  r.deliver({ Cc: 'cat@people.test', Subject: 'plans', 'Message-ID': '<p1@x.test>' });
  const all = r.mail('draft', 'replyall', 'p1@x.test');
  assert.equal(all.status, 0, all.stdout);
  assert.match(readFileSync(all.json.data.path, 'utf8'), /\nCc: cat@people\.test\n/);
  const fwd = r.mail('draft', 'forward', 'p1@x.test', '--to', 'dan@people.test');
  assert.equal(fwd.status, 0, fwd.stdout);
  assert.match(readFileSync(fwd.json.data.path, 'utf8'), /^From: .*\nTo: dan@people\.test\nSubject: Fwd: plans\n/);
  const none = r.mail('draft', 'reply', 'nope@x.test');
  assert.equal(none.status, 2, none.stdout);
});

test('mail draft --attach takes a path with spaces and refuses one that does not exist', (t) => {
  const r = rig(t);
  const att = r.file('my report.pdf', '%PDF-1.4\n');
  const res = r.mail('draft', 'new', '--to', 'ann@people.test', '--subject', 'file', '--attach', att);
  assert.equal(res.status, 0, res.stdout);
  const shown = r.mail('draft', 'show', res.json.data.id).json.data;
  assert.deepEqual(shown.attachments, [{ path: att, name: wrapped('my report.pdf'), size: 9 }]);
  const missing = r.mail('draft', 'new', '--to', 'ann@people.test', '--attach', join(r.M, 'gone.pdf'));
  assert.equal(missing.status, 1, missing.stdout);
  assert.equal(missing.json.error, `no such file: ${join(r.M, 'gone.pdf')}`);
});

test('mail drafts lists the drafts newest first, and leaves out a forward\'s attachment', (t) => {
  const r = rig(t);
  r.deliver({ Subject: 'old', 'Message-ID': '<o1@x.test>' });
  const a = r.mail('draft', 'new', '--to', 'ann@people.test', '--subject', 'first').json.data;
  const b = r.mail('draft', 'reply', 'o1@x.test').json.data;
  writeFileSync(join(r.drafts, 'fwd-0a0b0c0d-x.eml'), 'not a draft\n');
  // mtime decides the order; make the reply clearly newer.
  r.run('touch', ['-d', '2026-01-01', a.path]);
  const res = r.mail('drafts');
  assert.equal(res.status, 0, res.stdout);
  assert.deepEqual(res.json.data.map((d) => d.id), [b.id, a.id]);
  assert.deepEqual(res.json.data[1].to.map((p) => p.address), ['ann@people.test']);
  assert.equal(res.json.data[1].subject, wrapped('first'));
  assert.equal(res.json.data[0].subject, wrapped('Re: old'));
});

test('mail draft show prints what goes out, with a digest that changes with the draft', (t) => {
  const r = rig(t);
  const { id, path } = r.mail('draft', 'new', '--to', 'ann@people.test', '--subject', 'Hi', '--body-file', r.file('b.txt', 'hello\n')).json.data;
  // A second To line and a Bcc line, as a hand edit in Kakoune leaves them, show as they would go out.
  writeFileSync(path, readFileSync(path, 'utf8').replace('Subject:', 'To: bob@people.test\nBcc: me2@x.test\nSubject:'));
  const res = r.mail('draft', 'show', id);
  assert.equal(res.status, 0, res.stdout);
  const d = res.json.data;
  assert.equal(d.id, id);
  assert.equal(d.path, path);
  assert.equal(d.from.address, me);
  assert.deepEqual(d.to.map((p) => p.address), ['ann@people.test', 'bob@people.test']);
  assert.deepEqual(d.cc, []);
  assert.deepEqual(d.bcc.map((p) => p.address), ['me2@x.test']);
  assert.equal(d.subject, wrapped('Hi'));
  assert.equal(d.body, wrapped('hello'));
  assert.deepEqual(d.attachments, []);
  assert.match(d.digest, /^[0-9a-f]{16}$/);
  assert.equal(r.mail('draft', 'show', path).json.data.digest, d.digest, 'the path names the same draft');
  writeFileSync(path, readFileSync(path, 'utf8').replace('hello', 'hello!'));
  assert.notEqual(r.mail('draft', 'show', id).json.data.digest, d.digest);
});

test("a draft's attachment changing changes the digest", (t) => {
  const r = rig(t);
  const att = r.file('a.txt', 'one\n');
  const { id } = r.mail('draft', 'new', '--to', 'ann@people.test', '--attach', att).json.data;
  const before = r.mail('draft', 'show', id).json.data.digest;
  writeFileSync(att, 'two\n');
  assert.notEqual(r.mail('draft', 'show', id).json.data.digest, before);
});

test('mail draft show names only drafts', (t) => {
  const r = rig(t);
  for (const arg of ['../../etc/passwd', '/etc/passwd', 'fwd-0a0b0c0d-x.eml']) {
    const res = r.mail('draft', 'show', arg);
    assert.equal(res.status, 1, `${arg}: ${res.stdout}`);
    assert.equal(res.json.error, `not a draft: ${arg}`);
  }
  const gone = r.mail('draft', 'show', '20260101-000000-abcdef');
  assert.equal(gone.status, 2, gone.stdout);
});
