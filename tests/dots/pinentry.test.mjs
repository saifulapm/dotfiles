// dots-pinentry as gpg-agent runs it: Assuan on stdin and stdout, with the shell's socket played by a node server.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { chmodSync, mkdirSync, mkdtempSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { delimiter, join } from 'node:path';
import { execFileSync, spawn } from 'node:child_process';
import { createServer } from 'node:net';

const bin = new URL('../../bin/dots-pinentry', import.meta.url).pathname;

function scratch() {
  const root = mkdtempSync(join(tmpdir(), 'dots-pinentry-'));
  const stubs = join(root, 'stubs');
  mkdirSync(stubs);
  mkdirSync(join(root, 'run'));
  mkdirSync(join(root, 'state', 'dots'), { recursive: true });
  // The fallbacks greet like a pinentry and name themselves and their arguments.
  for (const name of ['pinentry-curses', 'pinentry-qt']) {
    writeFileSync(join(stubs, name), `#!/bin/sh\necho "OK ${name} $*"\n`);
    chmodSync(join(stubs, name), 0o755);
  }
  const env = {
    ...process.env,
    XDG_RUNTIME_DIR: join(root, 'run'),
    XDG_STATE_HOME: join(root, 'state'),
    WAYLAND_DISPLAY: 'wayland-test',
    PATH: stubs + delimiter + process.env.PATH,
  };
  delete env.PINENTRY_USER_DATA;
  return { root, env, sock: join(root, 'run', 'dots-pinentry-wayland-test.sock'), marker: join(root, 'state', 'dots', 'locked') };
}

// The shell's side: each request line is handed to answer(), whose lines go back; null keeps the connection open unanswered.
async function shell(sock, answer) {
  const requests = [];
  const sockets = [];
  const closed = [];
  const server = createServer((s) => {
    sockets.push(s);
    let buf = '';
    s.on('data', (d) => {
      buf += d;
      let i;
      while ((i = buf.indexOf('\n')) >= 0) {
        const line = buf.slice(0, i);
        buf = buf.slice(i + 1);
        requests.push(line);
        const reply = answer(line, requests.length);
        if (reply !== null) s.end(reply.map((l) => l + '\n').join(''));
      }
    });
    s.on('close', () => closed.push(Date.now()));
  });
  await new Promise((r) => server.listen(sock, r));
  return { requests, sockets, closed, stop: () => new Promise((r) => { sockets.forEach((s) => s.destroy()); server.close(r); }) };
}

// Runs the stub, sends each command once the answer to the one before has come, and gathers the answers.
function run(env, commands, { waitFor = () => true } = {}) {
  const p = spawn(bin, ['--display', 'x'], { env, stdio: ['pipe', 'pipe', 'pipe'] });
  // A fallback that answers and exits closes stdin before the next command.
  p.stdin.on('error', () => {});
  const lines = [];
  let buf = '';
  let sent = 0;
  const next = () => {
    if (sent < commands.length) p.stdin.write(commands[sent++] + '\n');
    else p.stdin.end();
  };
  p.stdout.on('data', (d) => {
    buf += d;
    let i;
    while ((i = buf.indexOf('\n')) >= 0) {
      const line = buf.slice(0, i);
      buf = buf.slice(i + 1);
      lines.push(line);
      if (/^(OK|ERR)\b/.test(line) && waitFor(lines)) next();
    }
  });
  let stderr = '';
  p.stderr.on('data', (d) => (stderr += d));
  const done = new Promise((resolve) => p.on('close', (code) => resolve({ code, lines, stderr })));
  return { p, done };
}

test('a passphrase request carries the description, prompt and error to the shell and relays its escaped answer', async () => {
  const { env, sock } = scratch();
  const sh = await shell(sock, () => ['D p%25ss%0Awörd', 'OK']);
  const { done } = run(env, ['OPTION ttyname=/dev/pts/1', 'SETDESC Please enter%0Athe passphrase', 'SETPROMPT Passphrase:', 'SETERROR Bad Passphrase (try 2 of 3)', 'GETPIN', 'BYE']);
  const r = await done;
  await sh.stop();
  assert.equal(r.code, 0, r.stderr);
  assert.deepEqual(r.lines, ['OK Pleased to meet you', 'OK', 'OK', 'OK', 'OK', 'D p%25ss%0Awörd', 'OK', 'OK closing connection']);
  assert.deepEqual(sh.requests, ['passphrase\tPlease enter%0Athe passphrase\tPassphrase:\tBad Passphrase (try 2 of 3)']);
});

test('Esc on the card reaches gpg as the cancel error', async () => {
  const { env, sock } = scratch();
  const sh = await shell(sock, () => ['ERR 83886179 Operation cancelled']);
  const r = await run(env, ['SETDESC x', 'GETPIN', 'BYE']).done;
  await sh.stop();
  assert.deepEqual(r.lines.slice(2), ['ERR 83886179 Operation cancelled', 'OK closing connection']);
});

test('a shell that goes away without answering cancels the request instead of hanging gpg', async () => {
  const { env, sock } = scratch();
  const sh = await shell(sock, () => []);
  const r = await run(env, ['GETPIN', 'BYE']).done;
  await sh.stop();
  assert.deepEqual(r.lines.slice(1), ['ERR 83886179 Operation cancelled', 'OK closing connection']);
});

// gpg-agent keeps one pinentry across its three tries, and the error resets with each GETPIN.
test('a retry in the same run asks again with the error, and the error is gone after that', async () => {
  const { env, sock } = scratch();
  const sh = await shell(sock, () => ['D x', 'OK']);
  const r = await run(env, ['SETDESC d', 'GETPIN', 'SETERROR Bad Passphrase (try 2 of 3)', 'GETPIN', 'GETPIN', 'BYE']).done;
  await sh.stop();
  assert.equal(r.code, 0);
  assert.deepEqual(sh.requests, ['passphrase\td\t\t', 'passphrase\td\t\tBad Passphrase (try 2 of 3)', 'passphrase\td\t\t']);
});

test('a tab in gpg\'s text is escaped, so the request keeps its four fields', async () => {
  const { env, sock } = scratch();
  const sh = await shell(sock, () => ['D x', 'OK']);
  await run(env, ['SETDESC a\tb', 'GETPIN', 'BYE']).done;
  await sh.stop();
  assert.deepEqual(sh.requests, ['passphrase\ta%09b\t\t']);
});

test('a confirmation asks for the confirm card and relays allow and deny', async () => {
  const { env, sock } = scratch();
  const sh = await shell(sock, (_, n) => (n === 1 ? ['OK'] : ['ERR 83886194 Not confirmed']));
  const r = await run(env, ['SETDESC Allow this?', 'CONFIRM', 'CONFIRM', 'BYE']).done;
  await sh.stop();
  assert.deepEqual(sh.requests, ['confirm\tAllow this?\t\t', 'confirm\tAllow this?\t\t']);
  assert.deepEqual(r.lines.slice(2), ['OK', 'ERR 83886194 Not confirmed', 'OK closing connection']);
});

test('GETINFO answers what gpg-agent asks, and other commands are accepted', async () => {
  const { env, sock } = scratch();
  const sh = await shell(sock, () => ['OK']);
  const { p, done } = run(env, ['GETINFO pid', 'GETINFO flavor', 'SETTITLE t', 'SETKEYINFO n/ABC', 'SETTIMEOUT 0', 'RESET', 'BYE']);
  const r = await done;
  await sh.stop();
  assert.deepEqual(r.lines, ['OK Pleased to meet you', `D ${p.pid}`, 'OK', 'D dots', 'OK', 'OK', 'OK', 'OK', 'OK', 'OK closing connection']);
});

test('while the screen is locked a request is cancelled at once and never reaches the shell', async () => {
  const { env, sock, marker } = scratch();
  writeFileSync(marker, '1761000000\n');
  const sh = await shell(sock, () => ['D x', 'OK']);
  const t0 = Date.now();
  const r = await run(env, ['GETPIN', 'BYE']).done;
  await sh.stop();
  assert.ok(Date.now() - t0 < 2000);
  assert.deepEqual(r.lines.slice(1), ['ERR 83886179 Operation cancelled', 'OK closing connection']);
  assert.deepEqual(sh.requests.filter((l) => l !== ''), []);
});

test('an empty lock marker, left by an unlock, asks as usual', async () => {
  const { env, sock, marker } = scratch();
  writeFileSync(marker, '');
  const sh = await shell(sock, () => ['D x', 'OK']);
  const r = await run(env, ['GETPIN', 'BYE']).done;
  await sh.stop();
  assert.deepEqual(r.lines.slice(1, 3), ['D x', 'OK']);
});

test('over SSH the curses pinentry takes the request, with gpg-agent\'s arguments', async () => {
  const { env, sock } = scratch();
  const sh = await shell(sock, () => ['D x', 'OK']);
  const r = await run({ ...env, PINENTRY_USER_DATA: 'curses' }, ['BYE']).done;
  await sh.stop();
  assert.equal(r.lines[0], 'OK pinentry-curses --display x');
});

test('with no shell socket pinentry-qt takes the request', async () => {
  const { env } = scratch();
  const r = await run(env, ['BYE']).done;
  assert.equal(r.lines[0], 'OK pinentry-qt --display x');
});

test('a socket a killed shell left behind falls back to pinentry-qt', async () => {
  const { env, sock } = scratch();
  // A bound socket nobody listens on, as a SIGKILLed shell leaves it.
  execFileSync('python3', ['-c', `import socket; socket.socket(socket.AF_UNIX).bind(${JSON.stringify(sock)})`]);
  const r = await run(env, ['BYE']).done;
  assert.equal(r.lines[0], 'OK pinentry-qt --display x');
});

// gpg-agent interrupts its pinentry when the client goes, such as a Ctrl+C on pass; the card must not stay up.
test('an interrupt while the card is up closes the connection to the shell', async () => {
  const { env, sock } = scratch();
  const sh = await shell(sock, () => null);
  const { p, done } = run(env, ['GETPIN']);
  while (sh.requests.length === 0) await new Promise((r) => setTimeout(r, 20));
  const t0 = Date.now();
  p.kill('SIGINT');
  const r = await done;
  while (sh.closed.length < 2 && Date.now() - t0 < 2000) await new Promise((r) => setTimeout(r, 20));
  await sh.stop();
  assert.notEqual(r.code, 0);
  assert.equal(sh.closed.length, 2, 'the probe and the request both closed');
  assert.ok(sh.closed[1] - t0 < 300, `the request closed ${sh.closed[1] - t0} ms after the interrupt`);
});
