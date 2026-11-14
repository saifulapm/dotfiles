// bin/kak-mail on a scratch notmuch store (tests/home/mail-rig.mjs): what a sender writes into a mail reaches notmuch as data, never as query syntax or shell.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync } from 'node:fs';
import { join } from 'node:path';
import { mailRig } from './mail-rig.mjs';

// A Message-ID is the sender's text: quotes, $( ), %{ } and braces all have to come back as the one message.
function hostile(t) {
  const r = mailRig(t);
  const pwned = join(r.M, 'PWNED');
  const boundary = 'b0';
  r.deliver(
    { 'Message-ID': `<a'$(touch ${pwned})'%{x}}@x.test>`, 'MIME-Version': '1.0', 'Content-Type': `multipart/mixed; boundary="${boundary}"` },
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
