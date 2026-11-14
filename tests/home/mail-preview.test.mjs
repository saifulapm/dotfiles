// bin/mail preview on a scratch notmuch store (tests/home/mail-rig.mjs): the HTML part as a 0600 file headless Chromium opens without one request leaving, until --images lets the images through.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawn, spawnSync } from 'node:child_process';
import { existsSync, mkdirSync, readdirSync, readFileSync, statSync, utimesSync, writeFileSync } from 'node:fs';
import { createServer } from 'node:https';
import { join } from 'node:path';
import { setTimeout as sleep } from 'node:timers/promises';
import { mailRig, repo } from './mail-rig.mjs';

function rig(t) {
  const r = mailRig(t);
  mkdirSync(r.env.XDG_RUNTIME_DIR, { mode: 0o700 });
  const mail = (...args) => {
    const res = r.run(join(repo, 'bin/mail'), args);
    let json = null;
    try {
      json = JSON.parse(res.stdout);
    } catch {}
    return { ...res, json };
  };
  // A raw .eml, bytes as given, so a charset test holds the sender's own bytes.
  let n = 0;
  const raw = (bytes) => {
    writeFileSync(join(r.mail, 'icloud/INBOX/new', `raw${n++}.eml`), bytes);
    r.notmuch('new', '--quiet');
  };
  return { ...r, mail, raw, previews: join(r.env.XDG_RUNTIME_DIR, 'mail-preview') };
}

const html = (headers, body) => ({ 'MIME-Version': '1.0', 'Content-Type': 'text/html; charset=utf-8', ...headers, body });

function deliverHtml(r, id, body) {
  const { body: b, ...h } = html({ 'Message-ID': `<${id}>`, Subject: 'newsletter' }, body);
  r.deliver(h, b);
}

// An https listener on 127.0.0.1 with a certificate made for this run; it counts each request by path and each connection.
async function listener(t, dir) {
  const key = join(dir, 'key.pem');
  const cert = join(dir, 'cert.pem');
  const made = spawnSync('openssl', ['req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-keyout', key, '-out', cert, '-days', '1', '-subj', '/CN=127.0.0.1'], { encoding: 'utf8' });
  assert.equal(made.status, 0, made.stderr);
  const seen = { requests: [], connections: 0 };
  const s = createServer({ key: readFileSync(key), cert: readFileSync(cert) }, (q, res) => {
    seen.requests.push(q.url);
    res.writeHead(200, { 'content-type': q.url.endsWith('.css') ? 'text/css' : 'image/gif' });
    res.end();
  });
  s.on('connection', () => seen.connections++);
  await new Promise((resolve) => s.listen(0, '127.0.0.1', resolve));
  t.after(() => s.close());
  return { origin: `https://127.0.0.1:${s.address().port}`, seen };
}

// Headless Chromium loads FILE with a scratch profile and returns its DOM; certificate errors are ignored, so only the page's own policy can stop a load.
async function chromium(r, file) {
  const profile = join(r.M, `chromium-${Math.random().toString(36).slice(2)}`);
  const c = spawn('chromium-browser', ['--headless=new', '--no-first-run', '--disable-gpu', `--user-data-dir=${profile}`, '--ignore-certificate-errors',
    '--virtual-time-budget=3000', '--dump-dom', `file://${file}`], { env: r.env, timeout: 30000 });
  let dom = '';
  c.stdout.on('data', (d) => (dom += d));
  const code = await new Promise((resolve) => c.on('exit', resolve));
  assert.equal(code, 0);
  // A load the page started just before Chromium quit still reaches the listener.
  await sleep(300);
  return dom;
}

// Every way a mail can fetch while it is drawn, at the listener: an image, a stylesheet, an @import, a font, a refresh, a dns-prefetch, a preconnect, a base href and a quote that tries to leave srcdoc.
const fetching = (o) => `<html><head>
<meta http-equiv="refresh" content="0;url=${o}/refresh">
<META HTTP-EQUIV=Refresh CONTENT="0;url=${o}/refresh2">
<meta content="0;url=${o}/refresh3?a>b" http-equiv="refresh">
<base href="${o}/base/">
<link rel="dns-prefetch" href="${o}/">
<link rel="preconnect" href="${o}/">
<link rel="stylesheet" href="${o}/sheet.css">
<style>@import url(${o}/import.css); @font-face { font-family: X; src: url(${o}/font.woff); } body { font-family: X; }</style>
</head><body><p>Hello</p><img src="${o}/img.gif">"></iframe><p id="outside">left srcdoc</p></body></html>
`;

// The srcdoc attribute of the written file, read back as the mail's HTML.
const srcdoc = (file) => {
  const m = readFileSync(file, 'utf8').match(/<iframe [^>]*srcdoc="([^"]*)"/);
  assert.ok(m, 'no iframe srcdoc');
  return m[1].replaceAll('&lt;', '<').replaceAll('&gt;', '>').replaceAll('&quot;', '"').replaceAll('&#x27;', "'").replaceAll('&amp;', '&');
};

test('mail preview writes a 0600 file in a 0700 mail-preview folder under XDG_RUNTIME_DIR and prints its path', (t) => {
  const r = rig(t);
  deliverHtml(r, 'n@x.test', '<p>Hello</p>\n');
  const res = r.mail('preview', 'n@x.test');
  assert.equal(res.status, 0, res.stdout + res.stderr);
  const path = res.json.data.path;
  assert.ok(path.startsWith(`${r.previews}/`), path);
  assert.equal((statSync(path).mode & 0o777).toString(8), '600');
  assert.equal((statSync(r.previews).mode & 0o777).toString(8), '700');
  assert.match(srcdoc(path), /<p>Hello<\/p>/);
});

test('headless Chromium opening a preview makes no request, and the mail keeps no link, base or meta tag', async (t) => {
  const r = rig(t);
  const { origin, seen } = await listener(t, r.M);
  deliverHtml(r, 'f@x.test', fetching(origin));
  const res = r.mail('preview', 'f@x.test');
  assert.equal(res.status, 0, res.stdout + res.stderr);
  const dom = await chromium(r, res.json.data.path);
  assert.deepEqual(seen.requests, []);
  assert.equal(seen.connections, 0);
  // Chromium writes attributes with < as &lt;, so a raw tag in its DOM dump is one the mail put outside the iframe.
  assert.doesNotMatch(dom, /<p id="outside"/);
  // A dns-prefetch at an IP never reaches a listener, so the tags themselves must be gone.
  assert.doesNotMatch(srcdoc(res.json.data.path), /<(link|base|meta)[\s/>]/i);
});

test('with --images, the same mail makes one request, for the img', async (t) => {
  const r = rig(t);
  const { origin, seen } = await listener(t, r.M);
  deliverHtml(r, 'f@x.test', fetching(origin));
  const res = r.mail('preview', 'f@x.test', '--images');
  assert.equal(res.status, 0, res.stdout + res.stderr);
  await chromium(r, res.json.data.path);
  assert.deepEqual(seen.requests, ['/img.gif']);
});

test('a windows-1252 HTML part shows é in the preview, named in its header or only in its meta', async (t) => {
  const r = rig(t);
  const eml = (id, type, meta) => Buffer.concat([
    Buffer.from(`From: Jo <jo@people.test>\nTo: me@x.test\nSubject: cafe\nMessage-ID: <${id}>\nMIME-Version: 1.0\nContent-Type: ${type}\n\n<html><head>${meta}</head><body><p>caf`),
    Buffer.from([0xe9]),
    Buffer.from('</p></body></html>\n'),
  ]);
  r.raw(eml('hdr@x.test', 'text/html; charset=windows-1252', ''));
  r.raw(eml('meta@x.test', 'text/html', '<meta http-equiv="Content-Type" content="text/html; charset=windows-1252">'));
  for (const id of ['hdr@x.test', 'meta@x.test']) {
    const res = r.mail('preview', id);
    assert.equal(res.status, 0, res.stdout + res.stderr);
    const dom = await chromium(r, res.json.data.path);
    // Chromium writes the srcdoc attribute's < and > as &lt; and &gt;.
    assert.match(dom, /&lt;p&gt;café&lt;\/p&gt;/, id);
  }
});

test('the HTML part wins over the plain one of a multipart/alternative mail', (t) => {
  const r = rig(t);
  r.deliver({ 'Message-ID': '<alt@x.test>', 'MIME-Version': '1.0', 'Content-Type': 'multipart/alternative; boundary="b0"' },
    '--b0\nContent-Type: text/plain\n\nplain text\n--b0\nContent-Type: text/html\n\n<p>the html</p>\n--b0--\n');
  const res = r.mail('preview', 'alt@x.test');
  assert.equal(res.status, 0, res.stdout + res.stderr);
  assert.match(srcdoc(res.json.data.path), /<p>the html<\/p>/);
});

test('a preview older than an hour is gone after the next preview, and a newer one stays', (t) => {
  const r = rig(t);
  deliverHtml(r, 'n@x.test', '<p>Hello</p>\n');
  mkdirSync(r.previews, { mode: 0o700 });
  const old = join(r.previews, 'old.html');
  const recent = join(r.previews, 'recent.html');
  writeFileSync(old, 'old');
  writeFileSync(recent, 'recent');
  const ago = Date.now() / 1000 - 3601;
  utimesSync(old, ago, ago);
  const res = r.mail('preview', 'n@x.test');
  assert.equal(res.status, 0, res.stdout + res.stderr);
  assert.equal(existsSync(old), false);
  assert.equal(existsSync(recent), true);
});

test('two previews of one mail in the same second are two files', (t) => {
  const r = rig(t);
  deliverHtml(r, 'n@x.test', '<p>Hello</p>\n');
  const a = r.mail('preview', 'n@x.test').json.data.path;
  const b = r.mail('preview', 'n@x.test').json.data.path;
  assert.notEqual(a, b);
  assert.ok(existsSync(a) && existsSync(b));
});

test('a plain-text mail has no HTML part: exit 2 and nothing written', (t) => {
  const r = rig(t);
  r.deliver({ 'Message-ID': '<plain@x.test>' }, 'just text\n');
  const res = r.mail('preview', 'plain@x.test');
  assert.equal(res.status, 2, res.stdout + res.stderr);
  assert.equal(res.json.ok, false);
  assert.equal(res.json.error, 'no HTML part');
  assert.deepEqual(existsSync(r.previews) ? readdirSync(r.previews) : [], []);
});

test('with XDG_RUNTIME_DIR unset, preview refuses with exit 3', (t) => {
  const r = rig(t);
  deliverHtml(r, 'n@x.test', '<p>Hello</p>\n');
  const { XDG_RUNTIME_DIR, ...env } = r.env;
  const res = spawnSync(join(repo, 'bin/mail'), ['preview', 'n@x.test'], { env, encoding: 'utf8' });
  assert.equal(res.status, 3, res.stdout + res.stderr);
  assert.match(JSON.parse(res.stdout).error, /XDG_RUNTIME_DIR/);
});
