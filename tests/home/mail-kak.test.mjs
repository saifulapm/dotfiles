// mail.kak in headless kak on a scratch notmuch store (tests/home/mail-rig.mjs): a Message-ID from a mail buffer reaches kak-mail as data through o, A and <ret>.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { existsSync, mkdirSync, readFileSync, symlinkSync, writeFileSync } from 'node:fs';
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

// Opens the inbox as an unthreaded list, so its one row is the hostile id:<Message-ID>, runs mail-open (what <ret> maps to) on it, then COMMAND in the thread. Kakoune runs a prompt's candidates script in the background, so kak runs with the JSON UI: its menu_show message carries the candidates, and <tab><ret> sent back as keys picks the first one. url_open_cmd appends what mail-open-with opens to a file, so a picked link or saved attachment shows up there.
async function kak(r, command) {
  const out = join(r.M, 'out');
  const opened = join(r.M, 'opened');
  // The scratch HOME hides ~/.local/bin, where the kak pin installs, so it goes in by its real path.
  const env = { ...r.env, PATH: `${r.env.PATH}:${join(process.env.HOME, '.local/bin')}` };
  const script = [
    `set-option global url_open_cmd %{printf '%%s\\n' %s >>${opened}}`,
    'mail-list-open tag:inbox true',
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
  assert.deepEqual(k.menu, ['1 x.test/a'], k.debug);
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

// G runs mail-sync in the background and echoes what its exit code means; a fake mail-sync first on PATH exits CODE, and the second parameter of the JSON UI's draw_status, the status line, carries the echo.
async function syncStatus(t, code) {
  const r = mailRig(t);
  mkdirSync(join(r.M, 'run'), { mode: 0o700 });
  mkdirSync(r.env.XDG_CONFIG_HOME, { recursive: true });
  symlinkSync(join(repo, 'home/dot_config/kak'), join(r.env.XDG_CONFIG_HOME, 'kak'));
  const fake = join(r.M, 'fake-sync');
  mkdirSync(fake);
  writeFileSync(join(fake, 'mail-sync'), `#!/bin/sh\nexit ${code}\n`, { mode: 0o755 });
  const env = { ...r.env, PATH: `${fake}:${r.env.PATH}:${join(process.env.HOME, '.local/bin')}` };
  const k = spawn('kak', ['-ui', 'json', '-e', 'mail-sync'], { env, timeout: 30000 });
  const exited = new Promise((resolve) => k.on('exit', resolve));
  const statuses = [];
  let buf = '';
  k.stdout.on('data', (d) => {
    buf += d;
    for (let i; (i = buf.indexOf('\n')) >= 0; buf = buf.slice(i + 1)) {
      const m = JSON.parse(buf.slice(0, i));
      if (m.method === 'draw_status') statuses.push(m.params[1].map((atom) => atom.contents).join(''));
    }
  });
  const last = () => statuses.findLast((s) => s.startsWith('mail: ') && s !== 'mail: syncing…');
  for (let i = 0; i < 100 && !last(); i++) await sleep(50);
  k.stdin.write(JSON.stringify({ jsonrpc: '2.0', method: 'keys', params: ['<esc>', ':quit!<ret>'] }) + '\n');
  assert.equal(await exited, 0);
  return last();
}

for (const [code, said] of [
  [0, 'mail: synced'],
  [69, 'mail: fetch failed — showing what arrived'],
  [75, 'mail: another sync is running'],
  [1, 'mail: sync failed — see ~/.local/state/hey-mail/sync.log'],
]) {
  test(`G says "${said}" when mail-sync exits ${code}`, async (t) => {
    assert.equal(await syncStatus(t, code), said);
  });
}

test("' k discards a draft along with the mark a sent draft keeps beside it", (t) => {
  const r = mailRig(t);
  mkdirSync(join(r.M, 'run'), { mode: 0o700 });
  mkdirSync(r.env.XDG_CONFIG_HOME, { recursive: true });
  symlinkSync(join(repo, 'home/dot_config/kak'), join(r.env.XDG_CONFIG_HOME, 'kak'));
  const draft = join(r.M, 'gone.eml');
  writeFileSync(draft, 'From: Me <me@x.test>\nTo: a@x.test\nSubject: hi\n\nhello\n');
  writeFileSync(`${draft}.sent`, 'sent copy\n');
  const env = { ...r.env, PATH: `${r.env.PATH}:${join(process.env.HOME, '.local/bin')}` };
  const k = r.run('kak', ['-ui', 'dummy', '-e', `edit ${draft}; mail-discard; quit!`], { env, timeout: 20000 });
  assert.equal(k.status, 0, k.stderr);
  assert.equal(existsSync(draft), false);
  assert.equal(existsSync(`${draft}.sent`), false);
});

// Opens the inbox's one mail as a thread, presses KEYS there, and returns what url_open_cmd was handed and the last status line (the second parameter of the JSON UI's draw_status).
async function pressInThread(r, keys) {
  mkdirSync(r.env.XDG_RUNTIME_DIR, { recursive: true, mode: 0o700 });
  mkdirSync(r.env.XDG_CONFIG_HOME, { recursive: true });
  symlinkSync(join(repo, 'home/dot_config/kak'), join(r.env.XDG_CONFIG_HOME, 'kak'));
  const out = join(r.M, 'out');
  const opened = join(r.M, 'opened');
  const env = { ...r.env, PATH: `${r.env.PATH}:${join(process.env.HOME, '.local/bin')}` };
  const script = [
    `set-option global url_open_cmd %{printf '%%s\\n' %s >>${opened}}`,
    'mail-list-open tag:inbox true',
    'mail-open',
    `eval -draft %{ execute-keys '%' ; echo -to-file ${out}.thread %val{selection} }`,
  ].join('\n');
  const k = spawn('kak', ['-ui', 'json', '-e', script], { env, timeout: 30000 });
  const exited = new Promise((resolve) => k.on('exit', resolve));
  const send = (...params) => k.stdin.write(JSON.stringify({ jsonrpc: '2.0', method: 'keys', params }) + '\n');
  const statuses = [];
  let buf = '';
  k.stdout.on('data', (d) => {
    buf += d;
    for (let i; (i = buf.indexOf('\n')) >= 0; buf = buf.slice(i + 1)) {
      const m = JSON.parse(buf.slice(0, i));
      if (m.method === 'draw_status') statuses.push(m.params[1].map((atom) => atom.contents).join(''));
    }
  });
  for (let i = 0; i < 100 && !read(`${out}.thread`); i++) await sleep(50);
  const before = statuses.length;
  send(...keys);
  // The opener runs in the background; a refusal shows on the status line at once.
  for (let i = 0; i < 60 && !read(opened) && !statuses.slice(before).some(Boolean); i++) await sleep(50);
  await sleep(200);
  send('<esc>', ':quit!<ret>');
  assert.equal(await exited, 0);
  return { opened: read(opened), status: statuses.slice(before).filter(Boolean).at(-1) ?? '' };
}

for (const [keys, images] of [[['V'], false], [['<a-v>'], true]]) {
  test(`${keys[0]} in a thread opens a preview of its HTML mail${images ? ' with images' : ''}`, async (t) => {
    const r = mailRig(t);
    r.deliver({ 'Message-ID': '<news@x.test>', 'MIME-Version': '1.0', 'Content-Type': 'text/html; charset=utf-8' }, '<p>Shop now</p>\n');
    const k = await pressInThread(r, keys);
    const path = k.opened.trim();
    assert.ok(path.startsWith(join(r.env.XDG_RUNTIME_DIR, 'mail-preview/')), `${k.opened} / ${k.status}`);
    const page = readFileSync(path, 'utf8');
    assert.match(page, /Shop now/);
    assert.equal(page.includes('img-src https: data:'), images);
  });
}

test('V on a plain-text mail says no HTML part and opens nothing', async (t) => {
  const r = mailRig(t);
  r.deliver({ 'Message-ID': '<plain@x.test>' }, 'just text\n');
  const k = await pressInThread(r, ['V']);
  assert.equal(k.status, 'no HTML part');
  assert.equal(k.opened, '');
});

// Opens BOX on a store of 1,200 single-mail threads, presses each of KEYS in turn, and returns the list's mode line (draw_status's fourth parameter) after the open and after each key.
async function modelines(t, keys) {
  const r = mailRig(t);
  for (let i = 0; i < 1200; i++) {
    writeFileSync(join(r.mail, 'icloud/INBOX/new', `big${i}.eml`), `From: Ann <ann@people.test>\nTo: me@x.test\nSubject: mail ${i}\nMessage-ID: <big${i}@x.test>\n\nhello\n`);
  }
  r.notmuch('new', '--quiet');
  mkdirSync(r.env.XDG_RUNTIME_DIR, { mode: 0o700 });
  mkdirSync(r.env.XDG_CONFIG_HOME, { recursive: true });
  symlinkSync(join(repo, 'home/dot_config/kak'), join(r.env.XDG_CONFIG_HOME, 'kak'));
  const env = { ...r.env, PATH: `${r.env.PATH}:${join(process.env.HOME, '.local/bin')}` };
  const k = spawn('kak', ['-ui', 'json', '-e', 'mail-box Everything'], { env, timeout: 30000 });
  const exited = new Promise((resolve) => k.on('exit', resolve));
  const send = (...params) => k.stdin.write(JSON.stringify({ jsonrpc: '2.0', method: 'keys', params }) + '\n');
  let mode = '';
  let buf = '';
  k.stdout.on('data', (d) => {
    buf += d;
    for (let i; (i = buf.indexOf('\n')) >= 0; buf = buf.slice(i + 1)) {
      const m = JSON.parse(buf.slice(0, i));
      if (m.method === 'draw_status') mode = m.params[3].map((atom) => atom.contents).join('');
    }
  });
  const settled = async (was) => {
    for (let i = 0; i < 100 && (!mode.includes('rows') || mode === was); i++) await sleep(50);
    return mode;
  };
  const seen = [await settled('')];
  for (const key of keys) {
    send(key);
    seen.push(await settled(seen.at(-1)));
  }
  send('<esc>', ':quit!<ret>');
  assert.equal(await exited, 0);
  return seen;
}

test('] and [ page a long list by 500, and its strip says which rows it shows', async (t) => {
  const seen = await modelines(t, [']', '[']);
  assert.deepEqual(seen.map((m) => m.match(/rows [^·]*/)?.[0].trim()), ['rows 1–500 of 1200', 'rows 501–1000 of 1200', 'rows 1–500 of 1200']);
  assert.match(seen[0], /open/);
});
