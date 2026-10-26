// dots-taildrop against a fake tailscaled LocalAPI on a unix socket in a scratch dir, with a notify-send stub first on PATH that records its argv.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { chmodSync, existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { delimiter, join } from 'node:path';
import { createServer } from 'node:http';
import { spawn } from 'node:child_process';

const bin = new URL('../../bin/dots-taildrop', import.meta.url).pathname;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function until(what, fn, ms = 8000) {
  const end = Date.now() + ms;
  while (Date.now() < end) {
    if (fn()) return;
    await sleep(50);
  }
  assert.fail('timed out waiting for ' + what);
}

// The fake keeps tailscaled's inbox in a map and the requests it saw as "METHOD /path" lines; an empty listing with waitsec holds for a moment like the real long-poll, and its IPN bus streams the files still being received, as tailscaled repeats them while a transfer runs.
function fakeApi(sock) {
  const inbox = new Map();
  const seen = [];
  const watchers = new Set();
  let incoming = [];
  const setIncoming = (files) => {
    incoming = files;
    for (const w of watchers) w.write(JSON.stringify({ IncomingFiles: files }) + '\n');
  };
  const server = createServer(async (req, res) => {
    const url = new URL(req.url, 'http://x');
    seen.push(`${req.method} ${url.pathname}${url.search}`);
    assert.equal(req.headers.host, 'local-tailscaled.sock');
    if (api.denied) {
      res.statusCode = 403;
      res.end('file access denied');
      return;
    }
    if (url.pathname === '/localapi/v0/watch-ipn-bus') {
      res.setHeader('Content-Type', 'application/json');
      res.write(JSON.stringify({ Version: '1.98.8' }) + '\n');
      if (incoming.length) res.write(JSON.stringify({ IncomingFiles: incoming }) + '\n');
      watchers.add(res);
      req.on('close', () => watchers.delete(res));
      return;
    }
    const rest = url.pathname.slice('/localapi/v0/files/'.length);
    if (rest === '') {
      const wait = Math.min(Number(url.searchParams.get('waitsec') ?? 0), 1) * 1000;
      for (let t = 0; inbox.size === 0 && t < wait; t += 50) await sleep(50);
      res.setHeader('Content-Type', 'application/json');
      res.end(JSON.stringify(inbox.size ? [...inbox].map(([Name, b]) => ({ Name, Size: b.length })) : null));
      return;
    }
    const name = decodeURIComponent(rest);
    if (!inbox.has(name)) {
      res.statusCode = 500;
      res.end('file does not exist');
    } else if (req.method === 'DELETE') {
      inbox.delete(name);
      res.statusCode = 204;
      res.end();
    } else {
      res.setHeader('Content-Length', inbox.get(name).length);
      res.end(inbox.get(name));
    }
  });
  const api = {
    denied: false,
    inbox,
    seen,
    setIncoming,
    listen: () => new Promise((r) => server.listen(sock, r)),
    close: () => {
      for (const w of watchers) w.destroy();
      server.close();
    },
  };
  return api;
}

async function scratch(t, { socketUp = true, notifyFails = 0 } = {}) {
  const root = mkdtempSync(join(tmpdir(), 'taildrop-'));
  const home = join(root, 'home');
  const stubs = join(root, 'stubs');
  const rec = join(root, 'rec');
  for (const d of [home, stubs, rec]) mkdirSync(d);
  // Its first notifyFails calls fail, as notify-send does at boot before the shell owns notifications.
  writeFileSync(join(stubs, 'notify-send'), `#!/bin/bash\necho >>"${root}/tries"\n[ "$(wc -l <"${root}/tries")" -gt ${notifyFails} ] || exit 1\nprintf '%s\\0' "$@" >"${rec}/n.$(date +%s%N).$$"\n`);
  chmodSync(join(stubs, 'notify-send'), 0o755);
  const sock = join(root, 'tailscaled.sock');
  const api = fakeApi(sock);
  if (socketUp) await api.listen();
  const child = spawn(bin, [], {
    env: {
      PATH: stubs + delimiter + process.env.PATH,
      HOME: home,
      XDG_CONFIG_HOME: join(home, '.config'),
      XDG_STATE_HOME: join(home, '.local/state'),
      XDG_DATA_HOME: join(home, '.local/share'),
      XDG_CACHE_HOME: join(home, '.cache'),
      DOTS_TAILSCALED_SOCKET: sock,
    },
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  let log = '';
  child.stdout.on('data', (d) => (log += d));
  child.stderr.on('data', (d) => (log += d));
  t.after(() => {
    child.kill('SIGKILL');
    api.close();
    rmSync(root, { recursive: true, force: true });
  });
  const downloads = join(home, 'Downloads');
  const notes = () =>
    readdirSync(rec)
      .sort()
      .map((f) => readFileSync(join(rec, f), 'utf8').split('\0').slice(0, -1));
  return { root, home, downloads, api, child, notes, log: () => log, listen: api.listen };
}

const saved = (s) => (existsSync(s.downloads) ? readdirSync(s.downloads).sort() : []);
// A file still downloading sits in Downloads under its temp name until the rename, so a wait counts only the files that landed.
const landed = (s) => saved(s).filter((f) => !/^\.dots-taildrop-\d+\.tmp$/.test(f));

test('an arrival lands in Downloads, leaves the inbox, and raises one notification naming it', async (t) => {
  const s = await scratch(t);
  s.api.inbox.set('IMG_2041.HEIC', Buffer.from('first-bytes'));
  await until('the file in Downloads', () => saved(s).includes('IMG_2041.HEIC'), 5000);
  assert.equal(readFileSync(join(s.downloads, 'IMG_2041.HEIC'), 'utf8'), 'first-bytes');
  await until('the DELETE', () => s.api.seen.includes('DELETE /localapi/v0/files/IMG_2041.HEIC'));
  await until('the notification', () => s.notes().length === 1);
  const argv = s.notes()[0];
  assert.equal(argv[argv.indexOf('-a') + 1], 'Tailscale');
  const rest = argv.slice(argv.indexOf('--') + 1);
  assert.deepEqual(rest, ['Taildrop · 1 file', 'IMG_2041.HEIC']);
  assert.ok(argv.includes('string:x-dots-files:' + join(s.downloads, 'IMG_2041.HEIC')), JSON.stringify(argv));
  assert.deepEqual(saved(s), ['IMG_2041.HEIC']);
});

test('a second file with the same name is renamed with a counter and the first stays', async (t) => {
  const s = await scratch(t);
  s.api.inbox.set('IMG_2041.HEIC', Buffer.from('one'));
  await until('the first file', () => landed(s).length === 1);
  await until('the first inbox drain', () => s.api.inbox.size === 0);
  s.api.inbox.set('IMG_2041.HEIC', Buffer.from('two'));
  await until('the second file', () => landed(s).length === 2);
  assert.deepEqual(saved(s), ['IMG_2041 (1).HEIC', 'IMG_2041.HEIC']);
  assert.equal(readFileSync(join(s.downloads, 'IMG_2041.HEIC'), 'utf8'), 'one');
  assert.equal(readFileSync(join(s.downloads, 'IMG_2041 (1).HEIC'), 'utf8'), 'two');
  await until('the drain', () => s.api.inbox.size === 0);
  s.api.inbox.set('IMG_2041.HEIC', Buffer.from('three'));
  await until('the third file', () => landed(s).length === 3);
  assert.equal(readFileSync(join(s.downloads, 'IMG_2041 (2).HEIC'), 'utf8'), 'three');
});

test('ten files arriving together give ten files and one notification with the count', async (t) => {
  const s = await scratch(t);
  for (let i = 0; i < 10; i++) s.api.inbox.set(`photo-${i}.jpg`, Buffer.from('p' + i));
  await until('ten files', () => landed(s).length === 10);
  await until('the notification', () => s.notes().length >= 1);
  await sleep(2500);
  assert.equal(s.notes().length, 1);
  const argv = s.notes()[0];
  const rest = argv.slice(argv.indexOf('--') + 1);
  assert.equal(rest[0], 'Taildrop · 10 files');
  const hint = argv.find((a) => a.startsWith('string:x-dots-files:')).slice('string:x-dots-files:'.length);
  assert.deepEqual(hint.split('\n').sort(), saved(s).map((f) => join(s.downloads, f)));
});

test('a file still arriving when the others have landed joins their notification, however long it takes', async (t) => {
  const s = await scratch(t);
  await until('the first listing', () => s.api.seen.some((l) => l.startsWith('GET /localapi/v0/files/')));
  s.api.setIncoming([{ Name: 'b.mov', DeclaredSize: 100, Received: 10 }]);
  s.api.inbox.set('a.jpg', Buffer.from('a'));
  await until('a.jpg saved or held', () => s.api.seen.some((l) => l.startsWith('GET /localapi/v0/watch-ipn-bus')));
  await sleep(3500);
  assert.deepEqual(s.notes(), [], 'no notification while b.mov is still arriving');
  // tailscaled 1.98.8 announces a transfer once as it starts and never sends the empty list, so a file is done once the inbox lists it.
  s.api.inbox.set('b.mov', Buffer.from('b'));
  const listed = Date.now();
  await until('both files', () => landed(s).length === 2);
  await until('the notification', () => s.notes().length >= 1);
  assert.ok(Date.now() - listed < 5000, `the batch closed ${Date.now() - listed} ms after its last file was listed`);
  await sleep(2500);
  assert.equal(s.notes().length, 1);
  const argv = s.notes()[0];
  assert.equal(argv[argv.indexOf('--') + 1], 'Taildrop · 2 files');
});

test('a tailscaled that refuses file access says how to fix it once, not on every retry', async (t) => {
  const s = await scratch(t);
  s.api.denied = true;
  s.api.inbox.set('a.jpg', Buffer.from('a'));
  await until('the notification', () => s.notes().length >= 1);
  await sleep(4000);
  assert.equal(s.notes().length, 1);
  const argv = s.notes()[0];
  assert.deepEqual(argv.slice(argv.indexOf('--') + 1), ['Taildrop cannot save files', 'tailscaled refuses file access: run sudo tailscale set --operator=$USER once']);
  assert.ok(argv.includes('critical'));
  s.api.denied = false;
  await until('the file once allowed', () => landed(s).length === 1);
});

test('a notification sent before anything shows notifications is sent again until one does', async (t) => {
  const s = await scratch(t, { notifyFails: 2 });
  s.api.inbox.set('boot.jpg', Buffer.from('b'));
  await until('the notification', () => s.notes().length === 1, 12000);
  assert.equal(s.notes()[0][s.notes()[0].indexOf('--') + 1], 'Taildrop · 1 file');
});

test('with no socket at start the process keeps running, then catches the queued file once tailscaled is up', async (t) => {
  const s = await scratch(t, { socketUp: false });
  s.api.inbox.set('late.txt', Buffer.from('queued'));
  await sleep(1500);
  assert.equal(s.child.exitCode, null);
  assert.equal(s.child.signalCode, null);
  await s.listen();
  await until('the queued file', () => saved(s).includes('late.txt'), 10000);
  assert.equal(s.child.exitCode, null);
  assert.equal(s.log().split('\n').filter((l) => /not reachable/.test(l)).length, 1, s.log());
});

test('a sender-controlled name never escapes Downloads or reaches notify-send raw', async (t) => {
  const s = await scratch(t);
  s.api.inbox.set('../evil', Buffer.from('x'));
  s.api.inbox.set('a\nb.txt', Buffer.from('y'));
  s.api.inbox.set('invoice‮fdp.exe', Buffer.from('z'));
  await until('the two safe files', () => landed(s).length === 2);
  await until('the notification', () => s.notes().length >= 1);
  await sleep(2500);
  assert.deepEqual(saved(s), ['a_b.txt', 'invoice_fdp.exe']);
  assert.equal(existsSync(join(s.home, 'evil')), false);
  assert.equal(existsSync(join(s.root, 'evil')), false);
  assert.equal(s.api.seen.some((l) => l.startsWith('DELETE') && l.includes('evil')), false);
  assert.equal(s.notes().length, 1);
  for (const arg of s.notes()[0].filter((a) => !a.startsWith('string:x-dots-files:')).flatMap((a) => a.split('\n'))) assert.doesNotMatch(arg, /[\u0000-\u001f‪-‮⁦-⁩]/, JSON.stringify(arg));
  const hint = s.notes()[0].find((a) => a.startsWith('string:x-dots-files:'));
  assert.deepEqual(hint.slice('string:x-dots-files:'.length).split('\n').sort(), [join(s.downloads, 'a_b.txt'), join(s.downloads, 'invoice_fdp.exe')]);
});

test('dots install starts the receiver on a running machine, and restarts it whenever it or its unit changes', () => {
  const script = readFileSync(new URL('../../home/.chezmoiscripts/run_onchange_after_15-taildrop.sh.tmpl', import.meta.url), 'utf8');
  assert.match(script, /^# receiver and unit hashes: \{\{ .*bin\/dots-taildrop" \| include \| sha256sum \}\} \{\{ .*dots-taildrop\.service" \| include \| sha256sum \}\}$/m);
  assert.match(script, /systemctl --user daemon-reload 2>\/dev\/null && systemctl --user restart dots-taildrop\.service 2>\/dev\/null \|\| true/);
});
