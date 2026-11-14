// mail.kak in headless kak on a scratch notmuch store (tests/home/mail-rig.mjs): a Message-ID from a mail buffer reaches kak-mail as data through o, A and <ret>.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { existsSync, mkdirSync, readFileSync, symlinkSync } from 'node:fs';
import { join } from 'node:path';
import { setTimeout as sleep } from 'node:timers/promises';
import { mailRig, repo } from './mail-rig.mjs';

// The quote ends a shell '...' string and %{x}} ends a Kakoune %{...} block early; notmuch drops the spaces in a Message-ID, so ${IFS} stands in for the one touch needs.
function hostile(t) {
  const r = mailRig(t);
  const pwned = join(r.M, 'PWNED');
  const boundary = 'b0';
  r.deliver(
    { 'Message-ID': `<a'$(touch\${IFS}${pwned})'%{x}}@x.test>`, Subject: 'hostile id', 'MIME-Version': '1.0', 'Content-Type': `multipart/mixed; boundary="${boundary}"` },
    `--${boundary}\nContent-Type: text/plain\n\nsee https://x.test/a\n--${boundary}\nContent-Type: text/plain\nContent-Disposition: attachment; filename="a.txt"\n\nattached\n--${boundary}--\n`,
  );
  mkdirSync(join(r.M, 'run'), { mode: 0o700 });
  mkdirSync(r.env.XDG_CONFIG_HOME, { recursive: true });
  symlinkSync(join(repo, 'home/dot_config/kak'), join(r.env.XDG_CONFIG_HOME, 'kak'));
  return { ...r, pwned };
}

const read = (f) => (existsSync(f) ? readFileSync(f, 'utf8') : '');

// Opens the inbox list, runs mail-open (what <ret> maps to) on its one row, then COMMAND in the thread. Kakoune runs a prompt's candidates script in the background, so kak runs with the JSON UI: its menu_show message carries the candidates, and <tab><ret> sent back as keys picks the first one. url_open_cmd appends what mail-open-with opens to a file, so a picked link or saved attachment shows up there.
async function kak(r, command) {
  const out = join(r.M, 'out');
  const opened = join(r.M, 'opened');
  // The scratch HOME hides ~/.local/bin, where the kak pin installs, so it goes in by its real path.
  const env = { ...r.env, PATH: `${r.env.PATH}:${join(process.env.HOME, '.local/bin')}` };
  const script = [
    `set-option global url_open_cmd %{printf '%%s\\n' %s >>${opened}}`,
    'mail-box tag:inbox',
    'mail-open',
    `eval -draft %{ execute-keys '%' ; echo -to-file ${out}.thread %val{selection} }`,
    command,
  ].join('\n');
  const k = spawn('kak', ['-ui', 'json', '-e', script], { env, timeout: 30000 });
  const exited = new Promise((resolve) => k.on('exit', resolve));
  const keys = (...params) => k.stdin.write(JSON.stringify({ jsonrpc: '2.0', method: 'keys', params }) + '\n');
  let menu = null;
  let buf = '';
  k.stdout.on('data', (d) => {
    buf += d;
    for (let i; (i = buf.indexOf('\n')) >= 0; buf = buf.slice(i + 1)) {
      const m = JSON.parse(buf.slice(0, i));
      if (m.method === 'menu_show' && !menu) menu = m.params[0].map((item) => item.map((atom) => atom.contents).join(''));
    }
  });
  // A key sent before kak has drawn its client is dropped.
  for (let i = 0; i < 100 && !read(`${out}.thread`); i++) await sleep(50);
  for (let i = 0; i < 100 && command && !menu; i++) await sleep(50);
  if (menu) {
    keys('<tab>', '<ret>');
    // mail-open-with runs the opener in the background.
    for (let i = 0; i < 100 && !read(opened); i++) await sleep(50);
  }
  keys('<esc>', `:eval -buffer *debug* %{ write ${out}.debug }<ret>`, ':quit!<ret>');
  assert.equal(await exited, 0);
  return { menu, thread: read(`${out}.thread`), opened: read(opened), debug: read(`${out}.debug`) };
}

test('<ret> on a list row opens the thread of a mail whose Message-ID holds quotes and %{ }', async (t) => {
  const r = hostile(t);
  const k = await kak(r, '');
  assert.match(k.thread, /^Subject: hostile id$/m, k.debug);
  assert.equal(existsSync(r.pwned), false);
});

test('o in a thread offers the link of a mail whose Message-ID holds quotes and %{ }, and runs nothing', async (t) => {
  const r = hostile(t);
  const k = await kak(r, 'mail-links');
  assert.equal(existsSync(r.pwned), false);
  assert.deepEqual(k.menu, ['https://x.test/a'], k.debug);
  assert.equal(k.opened, 'https://x.test/a\n');
});

test('A in a thread offers a.txt of a mail whose Message-ID holds quotes and %{ }, saves it, and runs nothing', async (t) => {
  const r = hostile(t);
  const saved = join(r.env.HOME, 'Downloads/a.txt');
  const k = await kak(r, 'mail-attachments');
  assert.equal(existsSync(r.pwned), false);
  assert.equal(k.menu?.length, 1, k.debug);
  assert.match(k.menu[0], /^\d+: a\.txt \(text\/plain\)$/);
  assert.equal(k.opened, `${saved}\n`);
  // MIME counts the line break before a boundary as part of the boundary.
  assert.equal(readFileSync(saved, 'utf8'), 'attached');
});
