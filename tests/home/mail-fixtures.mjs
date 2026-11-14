// A scratch store holding a mail for every HEY box and every body shape kak-mail renders, dated in 2020 and read in UTC, so a render of it is the same bytes on any day.
import { join } from 'node:path';
import { readFileSync, writeFileSync } from 'node:fs';
import { mailRig } from './mail-rig.mjs';

const boundary = 'b0';
const mixed = { 'MIME-Version': '1.0', 'Content-Type': `multipart/mixed; boundary="${boundary}"` };

// [Message-ID, headers, body, tags to add]; every mail lands with inbox and unread.
const mails = [
  ['imbox@x.test', { From: 'Bob <bob@people.test>', Subject: 'lunch on friday' }, 'Friday at one?\n', ['+screened']],
  ['seen@x.test', { From: 'Bob <bob@people.test>', Subject: 'seen before' }, 'old news\n', ['+screened', '+seen']],
  ['scr1@x.test', { From: 'Carol <carol@new.test>', Subject: 'first note' }, 'hello from carol\n', []],
  ['scr2@x.test', { From: 'Carol <carol@new.test>', Subject: 'Re: first note', 'In-Reply-To': '<scr1@x.test>', References: '<scr1@x.test>' }, 'again\n', []],
  ['feed1@x.test', { From: 'News <news@feed.test>', Subject: 'weekly digest', 'List-Id': '<news.feed.test>' }, 'this week\n', ['+thefeed', '-inbox', '+archived']],
  ['feed2@x.test', { From: 'News <news@feed.test>', Subject: 'last week', 'List-Id': '<news.feed.test>' }, 'that week\n', ['+thefeed', '-inbox', '+archived', '-unread']],
  ['h1@shop.test', { From: 'Shop <hi@shop.test>', Subject: 'your receipt', 'List-Unsubscribe': '<https://shop.test/u>', 'MIME-Version': '1.0', 'Content-Type': 'text/html; charset=utf-8' },
    '<html><body><p>Hello <a href="https://shop.test/x?utm=1">Shop now</a></p></body></html>\n', ['+ledger/receipts', '+archived', '-inbox', '-unread']],
  ['later@x.test', { From: 'Dee <dee@people.test>', Subject: 'can you review' }, 'when you can\n', ['+screened', '+replylater', '-unread']],
  ['aside@x.test', { From: 'Eve <eve@people.test>', Subject: 'tickets' }, 'keep these\n', ['+screened', '+setaside', '-unread']],
  ['bubble@x.test', { From: 'Fay <fay@people.test>', Subject: 'ping me' }, 'bubble up\n', ['+bubbled', '-inbox']],
  ['read@x.test', { From: 'Gus <gus@people.test>', Subject: 'already read' }, 'read it\n', ['+screened', '-unread']],
  ['note@x.test', { From: 'Me <me@x.test>', Subject: 'a note' }, 'remember\n', ['+note', '-inbox', '-unread']],
  ['muted@x.test', { From: 'List <l@lists.test>', Subject: 'noisy thread' }, 'noise\n', ['+muted', '-inbox']],
  ['sent@x.test', { From: 'Me <me@x.test>', To: 'Bob <bob@people.test>', Subject: 'Re: lunch on friday' }, 'yes\n', ['+sent', '-inbox', '-unread']],
  ['t1@x.test', { From: 'Hal <hal@people.test>', Subject: 'plan', Date: 'Wed, 01 Jan 2020 09:00:00 +0000' }, 'one\n', ['+screened']],
  ['t2@x.test', { From: 'Me <me@x.test>', Subject: 'Re: plan', Date: 'Wed, 01 Jan 2020 10:00:00 +0000', 'In-Reply-To': '<t1@x.test>', References: '<t1@x.test>' }, 'two\n\n> one\n', ['+screened']],
  ['t3@x.test', { From: 'Hal <hal@people.test>', Subject: 'Re: plan', Date: 'Wed, 01 Jan 2020 11:00:00 +0000', 'In-Reply-To': '<t2@x.test>', References: '<t1@x.test> <t2@x.test>' }, 'three\n', ['+screened']],
  ['alt@x.test', { From: 'Ivy <ivy@people.test>', Subject: 'both parts', 'MIME-Version': '1.0', 'Content-Type': `multipart/alternative; boundary="${boundary}"` },
    `--${boundary}\nContent-Type: text/plain\n\nplain wins\n--${boundary}\nContent-Type: text/html\n\n<p>html loses</p>\n--${boundary}--\n`, ['+screened']],
  ['cp1252@x.test', { From: 'Jo <jo@people.test>', Subject: '=?windows-1252?q?caf=E9?=', 'MIME-Version': '1.0', 'Content-Type': 'text/plain; charset=windows-1252', 'Content-Transfer-Encoding': 'quoted-printable' }, 'un caf=E9 cr=E8me\n', ['+screened']],
  ['att@x.test', { From: 'Kim <kim@people.test>', Subject: 'the file', ...mixed },
    `--${boundary}\nContent-Type: text/plain\n\nsee attached, and https://x.test/doc\n--${boundary}\nContent-Type: application/pdf\nContent-Disposition: attachment; filename="report.pdf"\n\n%PDF-1.4\n--${boundary}--\n`, ['+screened']],
  ['fwd@x.test', { From: 'Lee <lee@people.test>', Subject: 'Fwd: old mail', ...mixed },
    `--${boundary}\nContent-Type: text/plain\n\nforwarding this\n--${boundary}\nContent-Type: message/rfc822\n\nFrom: Old <old@people.test>\nDate: Tue, 31 Dec 2019 08:00:00 +0000\nSubject: inner\n\ninner body\n--${boundary}--\n`, ['+screened']],
];

// The rig, with each mail delivered in order (so thread ids are the same each run) on its own January 2020 day, and the tags each box needs.
export function fixtureStore(t) {
  const r = mailRig(t);
  r.env.TZ = 'UTC';
  mails.forEach(([id, headers, body], i) => r.deliver({ Date: `Thu, ${String(i + 2).padStart(2, '0')} Jan 2020 12:00:00 +0000`, ...headers, 'Message-ID': `<${id}>` }, body));
  r.notmuch('tag', '-new', '--', '*');
  for (const [id, , , tags] of mails) if (tags.length) r.notmuch('tag', ...tags, '--', `id:${id}`);
  return r;
}

export const boxNames = ['Imbox', 'Screener', 'The Feed', 'Paper Trail', 'Reply Later', 'Set Aside', 'Bubbled Up', 'Read', 'Muted', 'Drafts', 'Sent', 'Everything'];

// What Kakoune shows of the store: the box list, then each box's list buffer and what kak-mail tells kak, then each thread oldest first; a thread opens last, since opening marks it read.
export function renderAll(r) {
  const out = join(r.M, 'render');
  const ran = (args) => {
    const res = r.kakMail(...args);
    if (res.status !== 0) throw new Error(`kak-mail ${args.join(' ')}: ${res.stderr}`);
    return res.stdout;
  };
  const parts = [`== boxes\n${ran(['boxes'])}`, `== boxes --maps\n${ran(['boxes', '--maps'])}`];
  for (const name of boxNames) {
    const said = ran(['list', '--out', out, name]);
    parts.push(`== list ${name}\n${readFileSync(out, 'utf8')}-- kak\n${said}`);
  }
  const threads = r.notmuch('search', '--output=threads', '--sort=oldest-first', '*').split('\n').filter(Boolean);
  for (const thread of threads) {
    const said = ran(['show', '--out', out, thread]);
    parts.push(`== show ${thread}\n${readFileSync(out, 'utf8')}-- kak\n${said}`);
  }
  return parts.join('');
}

export const goldenPath = new URL('./golden/mail-kak.txt', import.meta.url).pathname;

// Run once at a base commit: node tests/home/mail-fixtures.mjs write
if (process.argv[1] === new URL(import.meta.url).pathname && process.argv[2] === 'write') {
  const cleanups = [];
  const r = fixtureStore({ after: (f) => cleanups.push(f) });
  try {
    writeFileSync(goldenPath, renderAll(r));
  } finally {
    for (const f of cleanups) f();
  }
}
