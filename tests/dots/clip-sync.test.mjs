// dots-clip-serve as the socket hands it one connection, and dots-clip-push as wl-paste --watch runs it, with wl-paste, systemd-run, notify-send, tailscale and curl replaced by stubs.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { chmodSync, existsSync, mkdirSync, mkdtempSync, readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { delimiter, join } from 'node:path';
import { spawnSync } from 'node:child_process';

const bin = new URL('../../bin/', import.meta.url).pathname;

function scratch() {
  const root = mkdtempSync(join(tmpdir(), 'dots-clip-sync-'));
  const stubs = join(root, 'stubs');
  const runtime = join(root, 'run');
  mkdirSync(stubs);
  mkdirSync(runtime);
  const s = { root, runtime, clip: join(root, 'clip'), copied: join(root, 'copied'), log: join(root, 'calls.log') };
  writeFileSync(s.clip, 'on this machine');
  const stub = (name, body) => {
    writeFileSync(join(stubs, name), `#!/bin/sh\n${body}\n`);
    chmodSync(join(stubs, name), 0o755);
  };
  stub('wl-paste', `case "$*" in *--list-types*) echo text/plain ;; *) cat '${s.clip}' ;; esac`);
  // The body file is the last argument; the real unit reads it into wl-copy.
  stub('systemd-run', `echo "systemd-run" >>'${s.log}'\nfor a; do last=$a; done\ncp "$last" '${s.copied}'`);
  stub('notify-send', `echo "notify-send $*" >>'${s.log}'`);
  stub('tailscale', `case "$1" in
  status) echo '{"Peer":{"a":{"OS":"linux","Online":true,"DNSName":"nuc.tail.ts.net."},"b":{"OS":"linux","Online":false,"DNSName":"mini.tail.ts.net."},"c":{"OS":"iOS","Online":true,"DNSName":"iphone.tail.ts.net."}}}' ;;
  whois) echo '{"Node":{"ComputedName":"iphone"}}' ;;
esac`);
  // Each push logs its url and headers, and the body it sent.
  stub('curl', `for a; do case $a in @*) body=\${a#@} ;; esac; done\necho "curl $*" >>'${s.log}'\ncat "$body" >>'${s.root}/sent'`);
  s.env = { ...process.env, PATH: stubs + delimiter + process.env.PATH, XDG_RUNTIME_DIR: runtime };
  delete s.env.CLIPBOARD_STATE;
  return s;
}

const calls = (s) => (existsSync(s.log) ? readFileSync(s.log, 'utf8').trim().split('\n') : []);
const serve = (s, request, peer = '127.0.0.1') =>
  spawnSync(join(bin, 'dots-clip-serve'), [], { env: { ...s.env, REMOTE_ADDR: peer }, input: request, encoding: 'utf8' });
const post = (body, headers = []) => [`POST / HTTP/1.1`, `Content-Length: ${Buffer.byteLength(body)}`, ...headers, '', body].join('\r\n');

test('a GET answers with the clipboard\'s exact bytes', () => {
  const s = scratch();
  const r = serve(s, 'GET / HTTP/1.1\r\n\r\n');
  assert.equal(r.status, 0);
  assert.match(r.stdout, /^HTTP\/1\.1 200 OK\r\n/);
  assert.match(r.stdout, /\r\nContent-Length: 15\r\n/);
  assert.ok(r.stdout.endsWith('\r\n\r\non this machine'));
});

test('a caller outside the tailnet is refused and the clipboard is left alone', () => {
  const s = scratch();
  const r = serve(s, post('from the LAN'), '::ffff:192.168.1.20');
  assert.match(r.stdout, /^HTTP\/1\.1 403 /);
  assert.deepEqual(calls(s), []);
});

test('a post from the phone becomes the clipboard, says who sent it, and is left for this machine to pass on', () => {
  const s = scratch();
  const r = serve(s, post('from the phone'), '100.64.1.2');
  assert.match(r.stdout, /^HTTP\/1\.1 200 OK\r\n/);
  assert.equal(readFileSync(s.copied, 'utf8'), 'from the phone');
  assert.deepEqual(calls(s), ['systemd-run', 'notify-send -a Clipboard -- Clipboard from iphone from the phone']);
  assert.equal(existsSync(join(s.runtime, 'dots-clip-sync.last')), false);
});

test('a relayed post becomes the clipboard quietly, and is marked so this machine does not send it back', () => {
  const s = scratch();
  serve(s, post('from the nuc', ['X-Clipboard-Relay: 1']), '127.0.0.1');
  assert.equal(readFileSync(s.copied, 'utf8'), 'from the nuc');
  assert.deepEqual(calls(s), ['systemd-run']);
  assert.equal(readFileSync(join(s.runtime, 'dots-clip-sync.last'), 'utf8'), 'from the nuc');
});

test('a post of what the clipboard already holds changes nothing', () => {
  const s = scratch();
  const r = serve(s, post('on this machine', ['X-Clipboard-Relay: 1']));
  assert.match(r.stdout, /\r\n\r\nunchanged\n$/);
  assert.deepEqual(calls(s), []);
});

const push = (s, text, env = {}) => spawnSync(join(bin, 'dots-clip-push'), [], { env: { ...s.env, ...env }, input: text, encoding: 'utf8' });

test('a copy goes to every online Linux peer once, marked as a relay', () => {
  const s = scratch();
  assert.equal(push(s, 'copied here').status, 0);
  const curls = calls(s).filter((c) => c.startsWith('curl'));
  assert.equal(curls.length, 1);
  assert.match(curls[0], /-H X-Clipboard-Relay: 1 .*http:\/\/nuc\.tail\.ts\.net\/$/);
  assert.equal(readFileSync(join(s.root, 'sent'), 'utf8'), 'copied here');
});

test('a sensitive copy, an empty one and one just received from a peer stay on this machine', () => {
  const s = scratch();
  push(s, 'a password', { CLIPBOARD_STATE: 'sensitive' });
  push(s, '');
  writeFileSync(join(s.runtime, 'dots-clip-sync.last'), 'from the nuc');
  push(s, 'from the nuc');
  assert.deepEqual(calls(s), []);
});
