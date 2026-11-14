// bin/kak-mail on a scratch notmuch store (tests/home/mail-rig.mjs): what a sender writes into a mail reaches notmuch as data, never as query syntax or shell.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync, rmSync, utimesSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { mailRig, repo } from './mail-rig.mjs';

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
  assert.equal(links.stdout, '1 x.test/a\n');
  const link = r.kakMail('link', r.id, '1 x.test/a');
  assert.equal(link.status, 0, link.stderr);
  assert.equal(link.stdout, 'https://x.test/a\n');
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
  // Screened in, as mail in the Screener stays unread when opened.
  r.notmuch('tag', '+screened', '--', '*');
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

test('screening in a sender on The Feed takes it off The Feed, so a sender has one class', (t) => {
  const r = mailRig(t);
  r.deliver({ From: 'Ann <ann@people.test>' });
  r.setDb('thefeed.db', 'joann@people.test\n');
  for (const action of ['feed', 'screen-in']) {
    const res = r.kakMail('hey', action, 'tag:new or tag:inbox or tag:thefeed');
    assert.equal(res.status, 0, res.stderr);
  }
  assert.equal(r.db('thefeed.db'), 'joann@people.test\n');
  assert.equal(r.db('screened.db'), 'ann@people.test\n');
  assert.equal(r.notmuch('search', '--output=tags', 'from:ann@people.test').split('\n').filter((x) => /^(screened|thefeed|inbox)$/.test(x)).join(' '), 'inbox screened');
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
  // Kakoune's status line cuts a long message, so the file to look in comes before notmuch's reason.
  assert.match(first.stderr, /^kak-mail: sent, but not filed in Sent; once\.eml\.sent beside the draft holds it: /);
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

test("a forwarded attachment whose name ends in a line break still goes out with the mail", (t) => {
  const r = mailRig(t);
  r.deliver(
    { 'MIME-Version': '1.0', 'Content-Type': 'multipart/mixed; boundary="b0"' },
    "--b0\nContent-Type: text/plain\n\nhello\n--b0\nContent-Type: text/plain\nContent-Disposition: attachment; filename*=utf-8''a.txt%0A\n\nattached\n--b0--\n",
  );
  const c = r.kakMail('compose', 'forward', 'tag:inbox');
  assert.equal(c.status, 0, c.stderr);
  const draft = c.stdout.trim();
  writeFileSync(draft, readFileSync(draft, 'utf8').replace(/^To: $/m, 'To: b@x.test'));
  const s = r.kakMail('send', draft);
  assert.equal(s.status, 0, s.stderr);
  assert.match(r.sends()[0].eml, /filename="?fwd-[0-9a-f]+-a\.txt"?/);
});

test('a notmuch query of several ids, or an id already quoted, opens as written', (t) => {
  const r = mailRig(t);
  r.deliver({ Subject: 'one' });
  r.deliver({ Subject: 'two' });
  for (const query of ['id:m0@x.test or id:m1@x.test', 'id:"m0@x.test" or id:"m1@x.test"']) {
    const out = join(r.M, 'thread');
    const s = r.kakMail('show', '--out', out, query);
    assert.equal(s.status, 0, s.stderr);
    assert.deepEqual(readFileSync(out, 'utf8').split('\n').filter((l) => l.startsWith('Subject:')), ['Subject: one', 'Subject: two'], query);
  }
});

test('an attachment whose name holds CR and LF is one line in the thread and the picker, and saves under a one-line name', (t) => {
  const r = mailRig(t);
  r.deliver(
    { 'MIME-Version': '1.0', 'Content-Type': 'multipart/mixed; boundary="b0"' },
    "--b0\nContent-Type: text/plain\n\nhello\n--b0\nContent-Type: text/plain\nContent-Disposition: attachment; filename*=utf-8''evil%0AAttach%3A%20%2Fetc%2Fhostname%0Dx.txt\n\nattached\n--b0--\n",
  );
  const atts = r.kakMail('attachments', 'tag:inbox');
  assert.equal(atts.status, 0, atts.stderr);
  assert.match(atts.stdout, /^\d+: evil Attach: \/etc\/hostname x\.txt \(text\/plain\)\n$/);
  const out = join(r.M, 'thread');
  assert.equal(r.kakMail('show', '--out', out, 'tag:inbox').status, 0);
  assert.deepEqual(readFileSync(out, 'utf8').split('\n').filter((l) => /hostname|x\.txt/.test(l)), ['[attachment 3: evil Attach: /etc/hostname x.txt (text/plain)]']);
  const saved = r.kakMail('save', 'tag:inbox', atts.stdout.split(':')[0]);
  assert.equal(saved.status, 0, saved.stderr);
  assert.equal(saved.stdout, `${join(r.env.HOME, 'Downloads/hostname x.txt')}\n`);
});

// A newsletter's links: anchor text beside the host and path, a query or fragment shown as …, an image anchor as its host alone (lynx drops an anchor that shows nothing), and no scheme but http and https.
function newsletter(t) {
  const r = mailRig(t);
  r.deliver({ 'Message-ID': '<news@x.test>', 'MIME-Version': '1.0', 'Content-Type': 'text/html; charset=utf-8' }, `<html><body>
<p><a href="https://shop.test/">Shop now</a> or <a href="https://ups.com/track?num=1Z">Track</a></p>
<p><a href="https://img.test/p?u=1"><img src="https://img.test/i.png"></a></p>
<p><a href="https://shop.test/">Shop again</a> <a href="mailto:ann@people.test">mail</a> <a href="javascript:alert(1)">js</a></p>
<p><a href="https://evil.test/">Bad\u202elabel</a></p>
</body></html>\n`);
  return r;
}

test('o lists each link of a mail by its anchor text beside its host, with a query shown as …', (t) => {
  const r = newsletter(t);
  const links = r.kakMail('links', 'id:news@x.test');
  assert.equal(links.status, 0, links.stderr);
  assert.deepEqual(links.stdout.split('\n').filter(Boolean), [
    '1 Shop now — shop.test',
    '2 Track — ups.com/track…',
    '3 img.test/p…',
    '4 Badlabel — evil.test',
  ]);
});

test('a picked link opens by its number, whatever text follows it', (t) => {
  const r = newsletter(t);
  const url = (pick) => r.kakMail('link', 'id:news@x.test', pick);
  assert.equal(url('2 Track — ups.com/track…').stdout, 'https://ups.com/track?num=1Z\n');
  assert.equal(url('3').stdout, 'https://img.test/p?u=1\n');
  const none = url('9 nothing');
  assert.equal(none.status, 1);
  assert.match(none.stderr, /no link 9/);
});

// A two-message thread: Ann's older mail holds a link and an attachment, Bob's reply a link of its own and one Ann's mail already had.
function twoInThread(t) {
  const r = mailRig(t);
  r.env.TZ = 'UTC';
  r.deliver({ 'Message-ID': '<old@x.test>', From: 'Ann <ann@people.test>', Date: 'Thu, 02 Jan 2020 12:00:00 +0000', 'MIME-Version': '1.0', 'Content-Type': 'multipart/mixed; boundary="b0"' },
    '--b0\nContent-Type: text/plain\n\nthe plan https://plan.test/doc\n--b0\nContent-Type: application/pdf\nContent-Disposition: attachment; filename="plan.pdf"\n\n%PDF-1.4\n--b0--\n');
  r.deliver({ 'Message-ID': '<new@x.test>', From: 'Bob <bob@people.test>', Date: 'Fri, 03 Jan 2020 12:00:00 +0000', 'In-Reply-To': '<old@x.test>', References: '<old@x.test>' },
    'see https://reply.test/x and https://plan.test/doc\n');
  const thread = r.notmuch('search', '--output=threads', 'id:new@x.test').trim();
  return { ...r, thread };
}

test("in a list, o on a thread lists every message's links, each with its sender and date", (t) => {
  const r = twoInThread(t);
  const links = r.kakMail('links', r.thread);
  assert.equal(links.status, 0, links.stderr);
  assert.deepEqual(links.stdout.split('\n').filter(Boolean), ['1 plan.test/doc (Ann, 2020-01-02)', '2 reply.test/x (Bob, 2020-01-03)']);
  assert.equal(r.kakMail('link', r.thread, '1').stdout, 'https://plan.test/doc\n');
});

test("in a list, A on a thread lists the older message's attachment with its sender and date, and saves it", (t) => {
  const r = twoInThread(t);
  const atts = r.kakMail('attachments', r.thread);
  assert.equal(atts.status, 0, atts.stderr);
  assert.equal(atts.stdout, '1: plan.pdf (application/pdf) (Ann, 2020-01-02)\n');
  const saved = r.kakMail('save', r.thread, '1');
  assert.equal(saved.status, 0, saved.stderr);
  assert.equal(readFileSync(saved.stdout.trim(), 'utf8'), '%PDF-1.4');
});

test('in a thread, o and A keep to the message under the cursor', (t) => {
  const r = twoInThread(t);
  assert.equal(r.kakMail('links', 'id:new@x.test').stdout, '1 reply.test/x\n2 plan.test/doc\n');
  assert.equal(r.kakMail('attachments', 'id:new@x.test').stdout, '');
});

const draftHead = (path) => readFileSync(path, 'utf8').split('\n\n')[0].split('\n');

test('compose mailto writes a draft to the address and subject, with cc and %40 read', (t) => {
  const r = mailRig(t);
  const a = r.kakMail('compose', 'mailto', 'mailto:ann@people.test?subject=Hi%20there');
  assert.equal(a.status, 0, a.stderr);
  assert.deepEqual(draftHead(a.stdout.trim()), ['From: Me <me@x.test>', 'To: ann@people.test', 'Subject: Hi there']);
  const b = r.kakMail('compose', 'mailto', 'mailto:ann%40people.test?cc=bob%40people.test&subject=a+b&body=line%20one%0Aline%20two');
  assert.equal(b.status, 0, b.stderr);
  const text = readFileSync(b.stdout.trim(), 'utf8');
  assert.deepEqual(draftHead(b.stdout.trim()), ['From: Me <me@x.test>', 'To: ann@people.test', 'Cc: bob@people.test', 'Subject: a+b']);
  assert.ok(text.includes('\n\nline one\nline two\n'), text);
});

test('a mailto keeps every field to one line and drops all but to, cc, subject and body', (t) => {
  const r = mailRig(t);
  const pwned = join(r.M, 'PWNED');
  const evil = encodeURIComponent(`x'}%{$(touch ${pwned})\r\nAttach: /etc/passwd\n\nbody`);
  const a = r.kakMail('compose', 'mailto', `mailto:ann@people.test,${evil}?subject=${evil}&bcc=spy@evil.test&attach=/etc/passwd&In-Reply-To=%3Cx%40y%3E&from=boss@evil.test`);
  assert.equal(a.status, 0, a.stderr);
  const head = draftHead(a.stdout.trim());
  assert.deepEqual(head.map((l) => l.split(':')[0]), ['From', 'To', 'Subject']);
  assert.equal(head[0], 'From: Me <me@x.test>');
  assert.equal(existsSync(pwned), false);
});

test('compose mailto refuses what is not a mailto URL', (t) => {
  const r = mailRig(t);
  const a = r.kakMail('compose', 'mailto', 'https://x.test/');
  assert.equal(a.status, 1);
  assert.match(a.stderr, /not a mailto/);
});

// 1,200 mails, each its own thread, written at once and indexed by one notmuch new.
function bigStore(t) {
  const r = mailRig(t);
  for (let i = 0; i < 1200; i++) {
    writeFileSync(join(r.mail, 'icloud/INBOX/new', `big${i}.eml`), `From: Ann <ann@people.test>\nTo: me@x.test\nSubject: mail ${i}\nMessage-ID: <big${i}@x.test>\nDate: ${new Date(Date.UTC(2020, 0, 1, 0, i)).toUTCString()}\n\nhello\n`);
  }
  r.notmuch('new', '--quiet');
  return r;
}

test('a list of 1,200 threads shows 500 rows from its offset and says which', (t) => {
  const r = bigStore(t);
  const out = join(r.M, 'list');
  const page = (...args) => {
    const res = r.kakMail('list', '--out', out, ...args);
    assert.equal(res.status, 0, res.stderr);
    return { said: res.stdout, rows: readFileSync(out, 'utf8').split('\n').filter(Boolean) };
  };
  const first = page('Everything');
  assert.equal(first.rows.length, 500);
  assert.match(first.said, /^set-option buffer mail_rows 'rows 1–500 of 1200'$/m);
  const second = page('--offset', '500', 'Everything');
  assert.match(second.said, /^set-option buffer mail_rows 'rows 501–1000 of 1200'$/m);
  assert.match(second.rows[0], /mail 699/);
  const last = page('--offset', '1000', 'Everything');
  assert.equal(last.rows.length, 200);
  assert.match(last.said, /^set-option buffer mail_rows 'rows 1001–1200 of 1200'$/m);
  // An offset past the end, as after archiving a last page's rows, shows the last page.
  assert.match(page('--offset', '1500', 'Everything').said, /^set-option buffer mail_offset 1000$/m);
});

test('o labels the links of a newsletter sent with a plain part beside its HTML one', (t) => {
  const r = mailRig(t);
  r.deliver({ 'Message-ID': '<alt@x.test>', 'MIME-Version': '1.0', 'Content-Type': 'multipart/alternative; boundary="b0"' },
    '--b0\nContent-Type: text/plain\n\nShop now: https://shop.test/\nTrack: https://ups.com/track?num=1Z\n--b0\nContent-Type: text/html\n\n<p><a href="https://shop.test/">Shop now</a> <a href="https://ups.com/track?num=1Z">Track</a></p>\n--b0--\n');
  const links = r.kakMail('links', 'id:alt@x.test');
  assert.equal(links.status, 0, links.stderr);
  assert.deepEqual(links.stdout.split('\n').filter(Boolean), ['1 Shop now — shop.test', '2 Track — ups.com/track…']);
});

test('a link whose host cannot be read, or that holds control characters, still lists as one clean line', (t) => {
  const r = mailRig(t);
  r.deliver({ 'Message-ID': '<odd@x.test>' }, 'see http://[2001:db8::1]/ and https://x.test:99999/a and https://ok.test/a‮gnp.exe\n');
  const links = r.kakMail('links', 'id:odd@x.test');
  assert.equal(links.status, 0, links.stderr);
  const rows = links.stdout.split('\n').filter(Boolean);
  assert.equal(rows.length, 3, links.stdout);
  assert.ok(rows.every((l) => !/[\x00-\x1f‪-‮⁦-⁩]/.test(l)), links.stdout);
});

test('a url linked first from an image and then from text lists under the text', (t) => {
  const r = mailRig(t);
  r.deliver({ 'Message-ID': '<img@x.test>', 'MIME-Version': '1.0', 'Content-Type': 'text/html; charset=utf-8' },
    '<p><a href="https://shop.test/"><img src="https://shop.test/i.png"></a></p><p><a href="https://shop.test/">Shop now</a></p>\n');
  assert.equal(r.kakMail('links', 'id:img@x.test').stdout, '1 Shop now — shop.test\n');
});

// Two drafts: one an agent wrote with mail draft, dated 3 Jan 2020, and an empty one Kakoune's compose wrote, dated 2 Jan 2020.
function twoDrafts(t) {
  const r = mailRig(t);
  r.env.TZ = 'UTC';
  const agent = r.run(join(repo, 'bin/mail'), ['draft', 'new', '--to', 'ann@people.test', '--subject', 'Hi']);
  assert.equal(agent.status, 0, agent.stderr);
  const byAgent = JSON.parse(agent.stdout).data.path;
  const composed = r.kakMail('compose', 'new');
  assert.equal(composed.status, 0, composed.stderr);
  const byKak = composed.stdout.trim();
  utimesSync(byAgent, new Date('2020-01-03T12:00:00Z'), new Date('2020-01-03T12:00:00Z'));
  utimesSync(byKak, new Date('2020-01-02T12:00:00Z'), new Date('2020-01-02T12:00:00Z'));
  return { ...r, byAgent, byKak };
}

test('the Drafts box counts the draft files and lists them newest first, an id of draft:PATH each', (t) => {
  const r = twoDrafts(t);
  const boxes = r.kakMail('boxes');
  assert.equal(boxes.status, 0, boxes.stderr);
  const names = boxes.stdout.split('\n').map((l) => l.slice(4, 16).trim());
  assert.deepEqual(names.slice(names.indexOf('Muted'), names.indexOf('Sent') + 1), ['Muted', 'Drafts', 'Sent']);
  assert.match(boxes.stdout, /^ d {2}Drafts {11}2$/m);
  const maps = r.kakMail('boxes', '--maps');
  assert.match(maps.stdout, /^map global mail-jump 'd' ':mail-box %\{Drafts\}<ret>' -docstring 'Drafts'$/m);
  const out = join(r.M, 'list');
  const list = r.kakMail('list', '--out', out, 'Drafts');
  assert.equal(list.status, 0, list.stderr);
  assert.equal(readFileSync(out, 'utf8'), [
    '2020-01-03 ann@people.test        Hi  []',
    '2020-01-02 (no recipient)           []',
  ].join('\n') + '\n');
  assert.match(list.stdout, new RegExp(`^set-option buffer mail_ids 'draft:${r.byAgent}' 'draft:${r.byKak}'$`, 'm'));
  assert.match(list.stdout, /^set-option buffer mail_rows 'rows 1–2 of 2'$/m);
});

test("e's archive refuses a draft row with kak-mail's error, and no tag changes", (t) => {
  const r = twoDrafts(t);
  r.deliver({});
  const before = r.notmuch('search', '--output=tags', '*');
  const res = r.kakMail('hey', 'archive', `draft:${r.byAgent}`);
  assert.equal(res.status, 1);
  assert.equal(res.stderr, 'kak-mail: a draft is not mail; it opens with <ret>\n');
  assert.equal(r.notmuch('search', '--output=tags', '*'), before);
});

test('the box list is the HEY boxes alone, with no Prev. Seen, Notes or Bundled', (t) => {
  const r = mailRig(t);
  const boxes = r.kakMail('boxes');
  assert.equal(boxes.status, 0, boxes.stderr);
  assert.deepEqual(boxes.stdout.trimEnd().split('\n').map((l) => l.slice(4, 16).trim()),
    ['Imbox', 'Screener', 'The Feed', 'Paper Trail', 'Reply Later', 'Set Aside', 'Bubbled Up', 'Read', 'Muted', 'Drafts', 'Sent', 'Everything']);
  assert.doesNotMatch(boxes.stdout, /Prev\. Seen|Notes|Bundled/);
});

test('mail with a seen or bundled tag from before still shows in the Imbox', (t) => {
  const r = mailRig(t);
  r.deliver({ 'Message-ID': '<old@x.test>' });
  r.notmuch('tag', '+screened', '+seen', '+bundled', '-new', '--', '*');
  const out = join(r.M, 'list');
  assert.equal(r.kakMail('list', '--out', out, 'Imbox').status, 0);
  assert.match(r.kakMail('list', '--out', out, 'Imbox').stdout, /mail_ids 'thread:/);
});

test('opening a Screener mail leaves it unread, and opening an Imbox thread marks it read', (t) => {
  const r = mailRig(t);
  r.deliver({ From: 'Shop <hi@shop.test>', 'Message-ID': '<h1@shop.test>' });
  r.deliver({ From: 'Bob <bob@people.test>', 'Message-ID': '<b1@x.test>' });
  r.notmuch('tag', '-new', '--', '*');
  r.notmuch('tag', '+screened', '--', 'id:b1@x.test');
  const out = join(r.M, 'show');
  const unread = (id) => r.notmuch('count', '--', `tag:unread and id:${id}`).trim();
  assert.equal(r.kakMail('show', '--out', out, 'id:h1@shop.test').status, 0);
  assert.equal(unread('h1@shop.test'), '1');
  const thread = r.notmuch('search', '--output=threads', '--', 'id:b1@x.test').trim();
  assert.equal(r.kakMail('show', '--out', out, thread).status, 0);
  assert.equal(unread('b1@x.test'), '0');
});

test('M mutes the thread: muted, out of the inbox, in the Muted box, and named in muted.db for dots sync', (t) => {
  const r = mailRig(t);
  r.deliver({ From: 'Bob <bob@people.test>', 'Message-ID': '<m1@x.test>' });
  r.deliver({ From: 'Ann <ann@people.test>', 'Message-ID': '<m2@x.test>', 'In-Reply-To': '<m1@x.test>', References: '<m1@x.test>' });
  r.notmuch('tag', '+screened', '-new', '--', '*');
  const res = r.kakMail('hey', 'mute', 'id:m2@x.test');
  assert.equal(res.status, 0, res.stderr);
  assert.equal(r.notmuch('count', '--', 'tag:muted and not tag:inbox').trim(), '2');
  const out = join(r.M, 'list');
  assert.equal(r.kakMail('list', '--out', out, 'Muted').status, 0);
  assert.equal(readFileSync(out, 'utf8').split('\n').filter(Boolean).length, 1);
  assert.equal(r.db('muted.db'), 'id:m1@x.test\n');
  assert.match(readFileSync(join(r.env.XDG_STATE_HOME, 'hey-mail/decided'), 'utf8'), /^\d+ mute id:m1@x\.test$/m);
  // A second mute of the same thread adds no line.
  assert.equal(r.kakMail('hey', 'mute', 'id:m1@x.test').status, 0);
  assert.equal(r.db('muted.db'), 'id:m1@x.test\n');
});

test('M is mapped in a list and a thread, and the help names it', () => {
  const kak = readFileSync(join(repo, 'home/dot_config/kak/autoload/tools/mail.kak'), 'utf8');
  const both = kak.slice(kak.indexOf('hook global WinSetOption filetype=mail-(list|thread)'));
  assert.match(both.slice(0, both.indexOf('\n}')), /map buffer normal M ':mail-hey mute<ret>'/);
  assert.match(kak, /^M +mute this thread/m);
});

test('unscreening a Paper Trail sender returns its last 12 months to the Screener unread, without ledger tags, and leaves older mail archived', (t) => {
  const r = mailRig(t);
  const day = (n) => new Date(Date.now() - n * 86400e3).toUTCString();
  r.deliver({ From: 'Shop <bills@shop.test>', 'Message-ID': '<new@shop.test>', Date: day(30) });
  r.deliver({ From: 'Shop <bills@shop.test>', 'Message-ID': '<old@shop.test>', Date: day(400) });
  r.notmuch('tag', '-new', '--', '*');
  assert.equal(r.kakMail('hey', 'papertrail', '--arg', 'receipts', 'id:new@shop.test').status, 0);
  // A phone drag into HEY/PaperTrail files under ledger/unfiled, and unscreen drops that too.
  r.notmuch('tag', '+ledger/unfiled', '--', 'id:new@shop.test');
  const res = r.kakMail('hey', 'unscreen', 'id:new@shop.test');
  assert.equal(res.status, 0, res.stderr);
  const tags = (id) => r.notmuch('search', '--output=tags', '--', `id:${id}`).split('\n').filter(Boolean);
  assert.deepEqual(tags('new@shop.test'), ['inbox', 'unread']);
  assert.deepEqual(tags('old@shop.test'), ['archived']);
  const out = join(r.M, 'list');
  assert.match(r.kakMail('list', '--out', out, 'Screener').stdout, /mail_ids 'id:new@shop\.test'$/m);
});

test('H c on a thread with a pending bubble cancels it: no bubble.db line, no bubble tag, back in the inbox', (t) => {
  const r = mailRig(t);
  r.deliver({ From: 'Bob <bob@people.test>', 'Message-ID': '<z1@x.test>' });
  r.deliver({ From: 'Bob <bob@people.test>', 'Message-ID': '<z2@x.test>' });
  r.notmuch('tag', '+screened', '-new', '--', '*');
  assert.equal(r.kakMail('hey', 'bubble', '--arg', 'tomorrow 9am', 'id:z1@x.test').status, 0);
  assert.equal(r.kakMail('hey', 'bubble', '--arg', 'tomorrow 9am', 'id:z2@x.test').status, 0);
  const res = r.kakMail('hey', 'clear', 'id:z1@x.test');
  assert.equal(res.status, 0, res.stderr);
  assert.doesNotMatch(r.db('bubble.db'), /z1@x\.test/);
  assert.match(r.db('bubble.db'), /^id:z2@x\.test \d+$/m, "another thread's bubble stays");
  const tags = r.notmuch('search', '--output=tags', '--', 'id:z1@x.test').split('\n').filter(Boolean);
  assert.ok(!tags.includes('bubble') && tags.includes('inbox'), tags.join(' '));
  assert.match(readFileSync(join(r.env.XDG_STATE_HOME, 'hey-mail/decided'), 'utf8'), /\d+ bubble id:z1@x\.test\n.*\n\d+ bubble id:z1@x\.test\n$/s);
});

test('a on an Imbox thread, then U, returns it to the Imbox; mail hey undo-last does the same, and a second undo has nothing to undo', (t) => {
  const r = mailRig(t);
  r.deliver({ From: 'Bob <bob@people.test>', 'Message-ID': '<u1@x.test>' });
  r.notmuch('tag', '+screened', '-new', '--', '*');
  const before = r.notmuch('dump', '--', 'id:u1@x.test');
  const thread = r.notmuch('search', '--output=threads', '--', 'id:u1@x.test').trim();
  assert.equal(r.kakMail('hey', 'archive', thread).status, 0);
  assert.notEqual(r.notmuch('dump', '--', 'id:u1@x.test'), before);
  const undone = r.kakMail('hey', 'undo-last');
  assert.equal(undone.status, 0, undone.stderr);
  assert.equal(r.notmuch('dump', '--', 'id:u1@x.test'), before);
  assert.equal(r.kakMail('hey', 'archive', thread).status, 0);
  const byAgent = r.run(join(repo, 'bin/mail'), ['hey', 'undo-last']);
  assert.equal(byAgent.status, 0, byAgent.stdout);
  assert.equal(r.notmuch('dump', '--', 'id:u1@x.test'), before);
  const again = r.kakMail('hey', 'undo-last');
  assert.equal(again.status, 1);
  assert.match(again.stderr, /nothing to undo/);
});

test('U after f puts the sender back in its class: no thefeed.db line, its screened.db line back, its mail as it was', (t) => {
  const r = mailRig(t);
  r.deliver({ From: 'Shop <news@shop.test>', 'Message-ID': '<f1@shop.test>' });
  r.notmuch('tag', '-new', '--', '*');
  assert.equal(r.kakMail('hey', 'screen-in', 'id:f1@shop.test').status, 0);
  const before = r.notmuch('dump', '--', 'id:f1@shop.test');
  assert.equal(r.kakMail('hey', 'feed', 'id:f1@shop.test').status, 0);
  assert.match(r.db('thefeed.db'), /news@shop\.test/);
  assert.equal(r.kakMail('hey', 'undo-last').status, 0);
  assert.equal(r.db('thefeed.db'), '');
  assert.equal(r.db('screened.db'), 'news@shop.test\n');
  assert.equal(r.notmuch('dump', '--', 'id:f1@shop.test'), before);
  assert.match(readFileSync(join(r.env.XDG_STATE_HOME, 'hey-mail/decided'), 'utf8').trim().split('\n').at(-1), /^\d+ sender news@shop\.test$/);
});

test('U is mapped in a list and a thread, and the help names it', () => {
  const kak = readFileSync(join(repo, 'home/dot_config/kak/autoload/tools/mail.kak'), 'utf8');
  const both = kak.slice(kak.indexOf('hook global WinSetOption filetype=mail-(list|thread)'));
  assert.match(both.slice(0, both.indexOf('\n}')), /map buffer normal U ':mail-undo<ret>'/);
  assert.match(kak, /^U +undo the last archive or Feed move/m);
});

// Saiful's ruling replaced m95's rule that a plain decision moved the whole organisation: it now carves the address out of its domain's line.
test('a decision on an address under an @domain line moves that address alone, and unscreen of another sender undoes the domain line', (t) => {
  const r = mailRig(t);
  r.deliver({ From: 'A <a@vendor.test>', 'Message-ID': '<va@vendor.test>' });
  r.deliver({ From: 'B <b@vendor.test>', 'Message-ID': '<vb@vendor.test>' });
  r.notmuch('tag', '+screened', '-new', '--', '*');
  r.setDb('screened.db', '@vendor.test\nbob@people.test\n');
  const res = r.kakMail('hey', 'feed', 'id:va@vendor.test');
  assert.equal(res.status, 0, res.stderr);
  assert.equal(res.stdout, 'feed: a@vendor.test\n');
  assert.equal(r.db('screened.db'), '@vendor.test\nbob@people.test\n');
  assert.equal(r.db('thefeed.db'), 'a@vendor.test\n');
  assert.equal(r.notmuch('count', '--', 'tag:thefeed and not tag:screened and not tag:inbox').trim(), '1');
  assert.match(readFileSync(join(r.env.XDG_STATE_HOME, 'hey-mail/decided'), 'utf8'), /^\d+ sender a@vendor\.test$/m);
  const u = r.kakMail('hey', 'unscreen', 'id:vb@vendor.test');
  assert.equal(u.stdout, 'unscreen: @vendor.test\n', u.stderr);
  assert.equal(r.db('screened.db'), 'bob@people.test\n');
  assert.equal(r.db('thefeed.db'), 'a@vendor.test\n');
  assert.equal(r.notmuch('count', '--', 'id:va@vendor.test and tag:thefeed').trim(), '1');
});

test('an address with a line of its own is decided alone, though an @domain line covers its domain', (t) => {
  const r = mailRig(t);
  r.deliver({ From: 'A <a@vendor.test>', 'Message-ID': '<va@vendor.test>' });
  r.notmuch('tag', '-new', '--', '*');
  r.setDb('screened.db', '@vendor.test\n');
  r.setDb('thefeed.db', 'a@vendor.test\n');
  assert.equal(r.kakMail('hey', 'screen-in', 'id:va@vendor.test').stdout, 'screen-in: a@vendor.test\n');
  assert.equal(r.db('screened.db'), '@vendor.test\na@vendor.test\n');
});
