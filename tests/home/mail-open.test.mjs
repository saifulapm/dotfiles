// bin/mail-open on a scratch store and a scratch kak session (tests/home/mail-rig.mjs): a mailto: URL opens a draft, a box name opens the box, and --help opens nothing. A fake dots-foot runs the kak client it is handed under the dummy UI and writes what that client shows.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, mkdirSync, readFileSync, symlinkSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { mailRig, repo } from './mail-rig.mjs';

function rig(t) {
  const r = mailRig(t);
  mkdirSync(r.env.XDG_RUNTIME_DIR, { mode: 0o700 });
  mkdirSync(r.env.XDG_CONFIG_HOME, { recursive: true });
  symlinkSync(join(repo, 'home/dot_config/kak'), join(r.env.XDG_CONFIG_HOME, 'kak'));
  const shown = join(r.M, 'shown');
  const fake = join(r.M, 'fake');
  mkdirSync(fake);
  // dots-foot --app-id=kak-mail kak -c mail -e CMD: run CMD ($6) in a dummy client, then write the buffer's name and text.
  writeFileSync(join(fake, 'dots-foot'), `#!/bin/sh
printf '%s\\n' "$@" > ${shown}.args
exec kak -ui dummy -c mail -e "$6; echo -to-file ${shown}.name %val{bufname}; eval -draft %{ execute-keys '%'; echo -to-file ${shown}.text %val{selection} }; quit!"
`, { mode: 0o755 });
  const env = { ...r.env, PATH: `${fake}:${r.env.PATH}:${join(process.env.HOME, '.local/bin')}` };
  const open = (...args) => r.run(join(repo, 'bin/mail-open'), args, { env, timeout: 20000 });
  // The session mail-open started lives in the scratch XDG_RUNTIME_DIR; it goes when the test ends.
  t.after(() => r.run('kak', ['-p', 'mail'], { env, input: 'kill!\n' }));
  const read = (f) => (existsSync(f) ? readFileSync(f, 'utf8') : '');
  return { ...r, open, shown: () => ({ args: read(`${shown}.args`), name: read(`${shown}.name`), text: read(`${shown}.text`) }) };
}

test('mail-open mailto: opens a draft to the address and subject', (t) => {
  const r = rig(t);
  const res = r.open('mailto:ann@people.test?subject=Hi%20there');
  assert.equal(res.status, 0, res.stderr);
  const s = r.shown();
  assert.match(s.name, /\/kak-mail\/drafts\/[^/]+\.eml$/, s.args);
  assert.match(s.text, /^To: ann@people.test$/m);
  assert.match(s.text, /^Subject: Hi there$/m);
});

test('mail-open BOX still opens the box', (t) => {
  const r = rig(t);
  r.deliver({ Subject: 'in the box' });
  r.notmuch('tag', '+screened', '--', '*');
  const res = r.open('Imbox');
  assert.equal(res.status, 0, res.stderr);
  const s = r.shown();
  assert.equal(s.name, '*mail:Imbox*');
  assert.match(s.text, /in the box/);
});

test('mail-open --help prints its usage and opens no window', (t) => {
  const r = rig(t);
  const res = r.open('--help');
  assert.equal(res.status, 0, res.stderr);
  assert.match(res.stdout, /^Usage: mail-open /);
  assert.equal(r.shown().args, '');
  const bad = r.open('--nope');
  assert.equal(bad.status, 1);
  assert.match(bad.stderr, /^Usage: mail-open /);
  assert.equal(r.shown().args, '');
});

test('the desktop entry hands mail-open the mailto URL', () => {
  const entry = readFileSync(join(repo, 'home/dot_local/share/applications/mail-open.desktop'), 'utf8');
  assert.match(entry, /^Exec=mail-open %u$/m);
  assert.match(entry, /^MimeType=x-scheme-handler\/mailto;$/m);
});
