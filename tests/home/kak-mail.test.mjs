// bin/kak-mail on a scratch notmuch store (tests/home/mail-rig.mjs): what a sender writes into a mail reaches notmuch as data, never as query syntax or shell.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { mailRig } from './mail-rig.mjs';

// A Message-ID is the sender's text: quotes, $( ), %{ } and braces all have to come back as the one message; notmuch drops a Message-ID's spaces, so ${IFS} stands in for touch's.
function hostile(t) {
  const r = mailRig(t);
  const pwned = join(r.M, 'PWNED');
  const boundary = 'b0';
  r.deliver(
    { 'Message-ID': `<a'$(touch\${IFS}${pwned})'%{x}}@x.test>`, 'MIME-Version': '1.0', 'Content-Type': `multipart/mixed; boundary="${boundary}"` },
    `--${boundary}\nContent-Type: text/plain\n\nsee https://x.test/a\n--${boundary}\nContent-Type: text/plain\nContent-Disposition: attachment; filename="a.txt"\n\nattached\n--${boundary}--\n`,
  );
  const id = r.notmuch('search', '--output=messages', '*').trim();
  assert.match(id, /^id:a'\$\(touch/);
  return { ...r, id, pwned };
}

test('links and attachments of a mail whose Message-ID holds quotes and $( ) list what it holds', (t) => {
  const r = hostile(t);
  const links = r.kakMail('links', r.id);
  assert.equal(links.status, 0, links.stderr);
  assert.equal(links.stdout, 'https://x.test/a\n');
  const atts = r.kakMail('attachments', r.id);
  assert.equal(atts.status, 0, atts.stderr);
  assert.match(atts.stdout, /^\d+: a\.txt \(text\/plain\)$/m);
  const part = atts.stdout.split(':')[0];
  const saved = r.kakMail('save', r.id, part);
  assert.equal(saved.status, 0, saved.stderr);
  assert.equal(saved.stdout.trim(), join(r.env.HOME, 'Downloads/a.txt'));
  assert.equal(existsSync(r.pwned), false);
});

test('a mail whose Message-ID holds quotes and $( ) opens, replies and archives', (t) => {
  const r = hostile(t);
  const shown = r.kakMail('show', '--out', join(r.M, 'thread'), r.id);
  assert.equal(shown.status, 0, shown.stderr);
  assert.equal(r.notmuch('count', 'tag:unread'), '0\n');
  const draft = r.kakMail('compose', 'reply', r.id);
  assert.equal(draft.status, 0, draft.stderr);
  const archived = r.kakMail('hey', 'archive', r.id);
  assert.equal(archived.status, 0, archived.stderr);
  assert.equal(r.notmuch('count', 'tag:archived'), '1\n');
  assert.equal(existsSync(r.pwned), false);
});

// Each db keeps its own line format: an address alone, `category address`, `address label` and `address days`.
const dbs = {
  'screened.db': (a) => a,
  'thefeed.db': (a) => a,
  'spam.db': (a) => a,
  'ledger.db': (a) => `Bills ${a}`,
  'autofile.db': (a) => `${a} Work`,
  'recycle.db': (a) => `${a} 30`,
};
const others = ['joann@people.test', 'ann+news@people.test', 'annXpeople.test@people.test', 'ANN@people.test.uk'];

test('unscreening a sender drops its line from every db and keeps every other sender, regex characters and all', (t) => {
  const r = mailRig(t);
  r.deliver({ From: 'Ann <ann@people.test>' });
  for (const [name, line] of Object.entries(dbs)) r.setDb(name, ['ann@people.test', ...others].map(line).join('\n') + '\n');
  const u = r.kakMail('hey', 'unscreen', 'tag:inbox');
  assert.equal(u.status, 0, u.stderr);
  for (const [name, line] of Object.entries(dbs)) assert.equal(r.db(name), others.map(line).join('\n') + '\n', name);
});

test('screen-in, feed and papertrail keep every other sender in their db', (t) => {
  for (const [action, name, extra] of [['screen-in', 'screened.db', []], ['feed', 'thefeed.db', []], ['papertrail', 'ledger.db', ['--arg', 'Bills']]]) {
    const r = mailRig(t);
    r.deliver({ From: 'Ann <ann@people.test>' });
    r.setDb(name, others.map(dbs[name]).join('\n') + '\n');
    const res = r.kakMail('hey', action, ...extra, 'tag:inbox');
    assert.equal(res.status, 0, res.stderr);
    assert.equal(r.db(name), [...others, 'ann@people.test'].map(dbs[name]).join('\n') + '\n', action);
  }
});

test('a sender whose address holds + is tagged alone', (t) => {
  const r = mailRig(t);
  r.deliver({ From: 'Ann <ann+news@people.test>' });
  r.deliver({ From: 'Ann <ann@people.test>' });
  const res = r.kakMail('hey', 'screen-in', `from:"ann+news@people.test"`);
  assert.equal(res.status, 0, res.stderr);
  assert.equal(r.notmuch('address', '--output=sender', '--output=address', 'tag:screened').trim(), 'ann+news@people.test');
});

test('the HEY dbs live in HEY_MAIL_DB_DIR, where the post-new hook reads them', (t) => {
  const r = mailRig(t);
  r.deliver({});
  r.env.HEY_MAIL_DB_DIR = join(r.M, 'elsewhere');
  const res = r.kakMail('hey', 'screen-in', 'tag:inbox');
  assert.equal(res.status, 0, res.stderr);
  assert.equal(readFileSync(join(r.M, 'elsewhere/screened.db'), 'utf8'), 'ann@people.test\n');
  assert.equal(r.db('screened.db'), '');
});

const headerLines = (draft) => readFileSync(draft, 'utf8').split('\n\n')[0].split('\n');

test('a reply to a Subject holding CR LF and a Bcc keeps it on the Subject line and sends to the sender alone', (t) => {
  const r = mailRig(t);
  r.deliver({ Subject: '=?utf-8?b?aGkNCkJjYzogZXZpbEB4LnRlc3Q=?=' });
  const c = r.kakMail('compose', 'reply', 'tag:inbox');
  assert.equal(c.status, 0, c.stderr);
  const draft = c.stdout.trim();
  const head = headerLines(draft);
  assert.ok(head.includes('Subject: Re: hi  Bcc: evil@x.test'), head.join('|'));
  assert.deepEqual(head.filter((l) => /^bcc:/i.test(l)), []);
  const s = r.kakMail('send', draft);
  assert.equal(s.status, 0, s.stderr);
  const [sent] = r.sends();
  const recipients = sent.eml.split(/\r?\n\r?\n/)[0].split(/\r?\n/).filter((l) => /^(to|cc|bcc):/i.test(l));
  assert.deepEqual(recipients, ['To: Ann <ann@people.test>']);
  assert.deepEqual(sent.args, ['-a', 'icloud', '--read-envelope-from', '-t']);
});

test('every other line break a header value can hold becomes a space in the draft', (t) => {
  const r = mailRig(t);
  r.deliver({ Subject: '=?utf-8?b?YQtiDGPChWTigKhl4oCpZhxnDUJjYzogZXZpbEB4LnRlc3Q=?=' });
  const c = r.kakMail('compose', 'reply', 'tag:inbox');
  assert.equal(c.status, 0, c.stderr);
  const head = headerLines(c.stdout.trim());
  assert.ok(head.includes('Subject: Re: a b c d e f g Bcc: evil@x.test'), head.join('|'));
  assert.deepEqual(head.filter((l) => /^bcc:/i.test(l)), []);
});

test("a forwarded attachment's name holding a line break adds no header to the draft", (t) => {
  const r = mailRig(t);
  r.deliver(
    { 'MIME-Version': '1.0', 'Content-Type': 'multipart/mixed; boundary="b0"' },
    "--b0\nContent-Type: text/plain\n\nhello\n--b0\nContent-Type: text/plain\nContent-Disposition: attachment; filename*=utf-8''a%0ABcc%3A%20evil%40x.test.txt\n\nattached\n--b0--\n",
  );
  const c = r.kakMail('compose', 'forward', 'tag:inbox');
  assert.equal(c.status, 0, c.stderr);
  const head = headerLines(c.stdout.trim());
  assert.deepEqual(head.filter((l) => /^bcc:/i.test(l)), [], head.join('|'));
  const attach = head.filter((l) => l.startsWith('Attach: '));
  assert.equal(attach.length, 1, head.join('|'));
  assert.ok(existsSync(attach[0].slice('Attach: '.length)), attach[0]);
});

test('a draft with two To lines sends to both', (t) => {
  const r = mailRig(t);
  const draft = join(r.M, 'two-to.eml');
  writeFileSync(draft, 'From: Me <me@x.test>\nTo: a@x.test\nTo: b@x.test\nSubject: hi\n\nhello\n');
  const s = r.kakMail('send', draft);
  assert.equal(s.status, 0, s.stderr);
  assert.doesNotMatch(s.stderr, /Traceback/);
  const [sent] = r.sends();
  const to = sent.eml.split(/\r?\n\r?\n/)[0].split(/\r?\n/).filter((l) => /^to:/i.test(l));
  assert.deepEqual(to, ['To: a@x.test, b@x.test']);
});

test('a draft whose Sent copy could not be filed is never sent a second time', (t) => {
  const r = mailRig(t);
  rmSync(join(r.mail, 'icloud/Sent Messages'), { recursive: true });
  const draft = join(r.M, 'once.eml');
  writeFileSync(draft, 'From: Me <me@x.test>\nTo: a@x.test\nSubject: hi\n\nhello\n');
  const first = r.kakMail('send', draft);
  assert.notEqual(first.status, 0);
  assert.equal(r.sends().length, 1);
  assert.equal(existsSync(draft), true);
  const second = r.kakMail('send', draft);
  assert.notEqual(second.status, 0);
  assert.match(second.stderr, /already sent/);
  assert.equal(r.sends().length, 1);
});

test('sending a reply takes its thread out of Reply Later and Set Aside', (t) => {
  const r = mailRig(t);
  r.deliver({});
  r.notmuch('tag', '+replylater', '+setaside', '--', '*');
  const c = r.kakMail('compose', 'reply', 'tag:inbox');
  assert.equal(c.status, 0, c.stderr);
  const s = r.kakMail('send', c.stdout.trim());
  assert.equal(s.status, 0, s.stderr);
  assert.equal(r.notmuch('count', 'tag:replylater or tag:setaside'), '0\n');
  assert.equal(r.notmuch('count', 'id:m0@x.test and tag:replied'), '1\n');
  assert.equal(r.notmuch('count', 'tag:sent'), '1\n');
});
