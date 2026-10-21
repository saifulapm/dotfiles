// dots-pass as the shell runs it: real pass, gpg and git in a scratch root, with the clipboard, the terminal and the editor played by stubs.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { chmodSync, copyFileSync, cpSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { delimiter, join } from 'node:path';
import { execFileSync, spawn } from 'node:child_process';

const bin = new URL('../../bin/dots-pass', import.meta.url).pathname;
const SECRET = 'JBSWY3DPEHPK3PXP';
const URI = `otpauth://totp/GitHub:saiful?secret=${SECRET}&issuer=GitHub`;
const real = (name) => execFileSync('which', [name], { encoding: 'utf8' }).trim();

function baseEnv(root) {
  const env = {
    ...process.env,
    HOME: join(root, 'home'),
    GNUPGHOME: join(root, 'gnupg'),
    PASSWORD_STORE_DIR: join(root, 'store'),
    XDG_CONFIG_HOME: join(root, 'config'),
    XDG_STATE_HOME: join(root, 'state'),
    XDG_CACHE_HOME: join(root, 'cache'),
    XDG_DATA_HOME: join(root, 'data'),
    XDG_RUNTIME_DIR: join(root, 'run'),
    GIT_AUTHOR_NAME: 'Test',
    GIT_AUTHOR_EMAIL: 'test@example.com',
    GIT_COMMITTER_NAME: 'Test',
    GIT_COMMITTER_EMAIL: 'test@example.com',
    GIT_CONFIG_COUNT: '1',
    GIT_CONFIG_KEY_0: 'init.defaultBranch',
    GIT_CONFIG_VALUE_0: 'main',
  };
  for (const k of ['PASSWORD_STORE_ENABLE_EXTENSIONS', 'PASSWORD_STORE_EXTENSIONS_DIR', 'DOTS_PASS_CLEAR_S', 'EDITOR', 'GPG_TTY']) delete env[k];
  return env;
}

// One key, one initialised git store and its bare remote, made once and copied for each test; the remote is a relative path so the copy still points at its own.
const template = mkdtempSync(join(tmpdir(), 'dots-pass-template-'));
{
  for (const d of ['home', 'config', 'state', 'cache', 'data', 'run']) mkdirSync(join(template, d));
  mkdirSync(join(template, 'gnupg'), { mode: 0o700 });
  const env = baseEnv(template);
  const x = (cmd, args, opts = {}) => execFileSync(cmd, args, { env, stdio: ['ignore', 'pipe', 'pipe'], encoding: 'utf8', ...opts });
  x('gpg', ['--batch', '--pinentry-mode', 'loopback', '--passphrase', '', '--quick-gen-key', 'Test <test@example.com>', 'default', 'default', 'never']);
  const fpr = x('gpg', ['--with-colons', '--list-secret-keys']).split('\n').find((l) => l.startsWith('fpr:')).split(':')[9];
  x('pass', ['init', fpr]);
  x('pass', ['git', 'init']);
  x('git', ['init', '--bare', join(template, 'remote.git')]);
  x('pass', ['git', 'remote', 'add', 'origin', '../remote.git']);
  x('pass', ['git', 'push', '-u', 'origin', 'HEAD']);
  try {
    x('gpgconf', ['--kill', 'gpg-agent']);
  } catch {}
}
process.on('exit', () => rmSync(template, { recursive: true, force: true }));

function scratch(t) {
  const root = mkdtempSync(join(tmpdir(), 'dots-pass-'));
  cpSync(template, root, { recursive: true });
  chmodSync(join(root, 'gnupg'), 0o700);
  const stubs = join(root, 'stubs');
  const rec = join(root, 'rec');
  mkdirSync(stubs);
  mkdirSync(rec);
  const put = (name, body) => {
    writeFileSync(join(stubs, name), `#!/bin/bash\n${body}\n`);
    chmodSync(join(stubs, name), 0o755);
  };
  // The shims log their arguments and run the real tool, so a test can look for a secret in what any process was started with.
  const shim = (name) => put(name, `echo "${name} $*" >>"$STUB_REC/argv.log"\nexec ${real(name)} "$@"`);
  for (const name of ['pass', 'zbarimg', 'oathtool']) shim(name);
  // A copy keeps the selection by staying alive, and the next copy ends it, as losing the selection ends the real one.
  put(
    'wl-copy',
    `echo "wl-copy $*" >>"$STUB_REC/argv.log"
case " $* " in *" --clear "*) echo clear >>"$STUB_REC/clears"; exit 0 ;; esac
echo "$*" >"$STUB_REC/wl-copy.args"
cat >"$STUB_REC/wl-copy.stdin"
[ ! -f "$STUB_REC/wl-copy.pid" ] || kill "$(cat "$STUB_REC/wl-copy.pid")" 2>/dev/null
echo $$ >"$STUB_REC/wl-copy.pid"
exec sleep 300`,
  );
  put('wl-paste', `echo "wl-paste $*" >>"$STUB_REC/argv.log"\n[ -f "$STUB_REC/clipboard.png" ] || exit 1\ncat "$STUB_REC/clipboard.png"`);
  // The shell's user manager need not have bin/ on PATH, so dots-pass runs from a dir of its own with dots-foot beside it, and that dir is not on PATH.
  const own = join(root, 'bin');
  mkdirSync(own);
  copyFileSync(bin, join(own, 'dots-pass'));
  chmodSync(join(own, 'dots-pass'), 0o755);
  writeFileSync(join(own, 'dots-foot'), `#!/bin/bash\necho "dots-foot $*" >>"$STUB_REC/argv.log"\n[ "$1" != -e ] || shift\n"$@"\n`);
  chmodSync(join(own, 'dots-foot'), 0o755);
  put('kak', `echo "edited in kak" >>"$1"`);
  const env = { ...baseEnv(root), PATH: stubs + delimiter + process.env.PATH, STUB_REC: rec, EDITOR: 'vim' };
  const ctx = { bin: join(own, 'dots-pass'), root, rec, env, groups: [], store: join(root, 'store'), state: join(root, 'state', 'dots') };
  t.after(() => {
    for (const pid of ctx.groups) {
      try {
        process.kill(-pid, 'SIGKILL');
      } catch {}
    }
    try {
      execFileSync('gpgconf', ['--kill', 'gpg-agent'], { env, stdio: 'ignore' });
    } catch {}
    rmSync(root, { recursive: true, force: true });
  });
  return ctx;
}

// Runs dots-pass in a group of its own, so the copy and the timer it leaves behind can be ended with the test.
function run(ctx, args, { input = '', env = {} } = {}) {
  return new Promise((resolve) => {
    const p = spawn(ctx.bin, args, { env: { ...ctx.env, ...env }, detached: true, stdio: ['pipe', 'pipe', 'pipe'] });
    ctx.groups.push(p.pid);
    let stdout = '';
    let stderr = '';
    p.stdout.on('data', (d) => (stdout += d));
    p.stderr.on('data', (d) => (stderr += d));
    p.on('error', (e) => resolve({ code: null, stdout, stderr: String(e) }));
    p.on('close', (code) => resolve({ code, stdout, stderr }));
    p.stdin.end(input);
  });
}

// Puts an entry in the store with the real pass, as the owner would; this commits locally and pushes nothing.
function seed(ctx, name, text) {
  execFileSync('/usr/bin/pass', ['insert', '-m', '-f', '--', name], { env: ctx.env, input: text, stdio: ['pipe', 'pipe', 'pipe'] });
}
const show = (ctx, name) => execFileSync('/usr/bin/pass', ['show', '--', name], { env: ctx.env, encoding: 'utf8' });
const rec = (ctx, name) => (existsSync(join(ctx.rec, name)) ? readFileSync(join(ctx.rec, name), 'utf8') : null);
const state = (ctx, name) => (existsSync(join(ctx.state, name)) ? readFileSync(join(ctx.state, name), 'utf8') : null);
const lastRemote = (ctx) => execFileSync('git', ['--git-dir', join(ctx.root, 'remote.git'), 'log', '-1', '--format=%s', 'main'], { encoding: 'utf8' }).trim();
const qr = (ctx, text) => execFileSync('qrencode', ['-o', join(ctx.rec, 'clipboard.png'), text]);
const until = async (fn, ms = 4000) => {
  for (const end = Date.now() + ms; Date.now() < end; await new Promise((r) => setTimeout(r, 25))) if (fn()) return true;
  return false;
};
const totp = () => execFileSync('oathtool', ['--totp', '-b', SECRET], { encoding: 'utf8' }).trim();

test('list puts recent entries first, then the rest in C order, with the otp column', async (t) => {
  const ctx = scratch(t);
  const names = ['web/github.com', 'web/a b', '-dash', 'otp/bank', 'zeta', 'mail', '.extensions/x', '.hidden/y', 'tab\tname'];
  for (const n of names) {
    mkdirSync(join(ctx.store, n, '..'), { recursive: true });
    writeFileSync(join(ctx.store, `${n}.gpg`), '');
  }
  mkdirSync(ctx.state, { recursive: true });
  writeFileSync(join(ctx.state, 'pass-recent'), 'zeta\nmail\ngone\n');
  writeFileSync(join(ctx.state, 'pass-otp'), 'web/github.com\n');
  const r = await run(ctx, ['list']);
  assert.equal(r.code, 0, r.stderr);
  assert.equal(r.stdout, 'zeta\t0\nmail\t0\n-dash\t0\notp/bank\t1\nweb/a b\t0\nweb/github.com\t1\n');
});

test('list of a missing store prints nothing and succeeds', async (t) => {
  const ctx = scratch(t);
  const r = await run(ctx, ['list'], { env: { PASSWORD_STORE_DIR: join(ctx.root, 'nowhere') } });
  assert.deepEqual([r.code, r.stdout, r.stderr], [0, '', '']);
});

test('copy puts the first line on wl-copy as sensitive, off argv, and records the use', async (t) => {
  const ctx = scratch(t);
  seed(ctx, 'web/github.com', 's3cret-Pw!\nuser: saiful\n');
  const r = await run(ctx, ['copy', 'web/github.com']);
  assert.equal(r.code, 0, r.stderr);
  assert.equal(rec(ctx, 'wl-copy.stdin'), 's3cret-Pw!');
  assert.equal(rec(ctx, 'wl-copy.args'), '--sensitive --foreground --trim-newline\n');
  assert.equal(state(ctx, 'pass-recent'), 'web/github.com\n');
  assert.doesNotMatch(rec(ctx, 'argv.log'), /s3cret-Pw/);
});

for (const name of ['web/my site', '-lead']) {
  test(`insert, copy, edit and delete work for the name "${name}"`, async (t) => {
    const ctx = scratch(t);
    assert.equal((await run(ctx, ['insert', name], { input: 'pw-one\n' })).code, 0);
    assert.equal((await run(ctx, ['exists', name])).code, 0);
    assert.equal((await run(ctx, ['copy', name])).code, 0);
    assert.equal(rec(ctx, 'wl-copy.stdin'), 'pw-one');
    assert.equal((await run(ctx, ['edit', name])).code, 0);
    assert.equal(show(ctx, name), 'pw-one\nedited in kak\n');
    assert.equal((await run(ctx, ['delete', name])).code, 0);
    assert.equal((await run(ctx, ['exists', name])).code, 1);
    assert.equal(state(ctx, 'pass-recent'), '');
  });
}

test('the clipboard is cleared when the timeout passes and the copy still holds it', async (t) => {
  const ctx = scratch(t);
  seed(ctx, 'a', 'pw\n');
  const t0 = Date.now();
  assert.equal((await run(ctx, ['copy', 'a'], { env: { DOTS_PASS_CLEAR_S: '0.4' } })).code, 0);
  assert.equal(rec(ctx, 'clears'), null, 'copy returned only after the clear');
  assert.ok(await until(() => rec(ctx, 'clears') === 'clear\n'), `no clear after ${Date.now() - t0} ms`);
});

test('a later copy before the timeout is not cleared by the earlier one', async (t) => {
  const ctx = scratch(t);
  seed(ctx, 'a', 'one\n');
  seed(ctx, 'b', 'two\n');
  await run(ctx, ['copy', 'a'], { env: { DOTS_PASS_CLEAR_S: '1' } });
  await run(ctx, ['copy', 'b'], { env: { DOTS_PASS_CLEAR_S: '30' } });
  await new Promise((r) => setTimeout(r, 1500));
  assert.equal(rec(ctx, 'clears'), null);
  assert.equal(rec(ctx, 'wl-copy.stdin'), 'two');
});

test('a failed decrypt copies nothing, records nothing and exits non-zero', async (t) => {
  const ctx = scratch(t);
  writeFileSync(join(ctx.store, 'broken.gpg'), 'not a gpg file');
  for (const name of ['broken', 'missing']) {
    const r = await run(ctx, ['copy', name]);
    assert.notEqual(r.code, 0);
    assert.match(r.stderr, /^dots-pass: [^\n]+\n$/);
  }
  assert.equal(rec(ctx, 'wl-copy.args'), null);
  assert.equal(state(ctx, 'pass-recent'), null);
});

test('otp copies the same code oathtool gives and tags the entry', async (t) => {
  const ctx = scratch(t);
  seed(ctx, 'web/github.com', `pw\n${URI}\n`);
  const before = totp();
  const r = await run(ctx, ['otp', 'web/github.com']);
  const after = totp();
  assert.equal(r.code, 0, r.stderr);
  const code = rec(ctx, 'wl-copy.stdin');
  assert.match(code, /^\d{6}$/);
  assert.ok(code === before || code === after, `${code} is neither ${before} nor ${after}`);
  assert.equal(state(ctx, 'pass-otp'), 'web/github.com\n');
  assert.equal(state(ctx, 'pass-recent'), 'web/github.com\n');
  // pass otp hands the secret to oathtool in argv, where any process could read it.
  assert.doesNotMatch(rec(ctx, 'argv.log'), new RegExp(SECRET));
});

test("otp follows the code's digits, period and algorithm", async (t) => {
  const ctx = scratch(t);
  seed(ctx, 'bank', `pw\notpauth://totp/Bank:me?secret=${SECRET}&digits=8&period=60&algorithm=SHA256\n`);
  const want = () => execFileSync('oathtool', ['--totp=sha256', '--time-step-size=60s', '--digits=8', '-b', SECRET], { encoding: 'utf8' }).trim();
  const before = want();
  const r = await run(ctx, ['otp', 'bank']);
  const after = want();
  assert.equal(r.code, 0, r.stderr);
  const code = rec(ctx, 'wl-copy.stdin');
  assert.ok(code === before || code === after, `${code} is neither ${before} nor ${after}`);
  assert.doesNotMatch(rec(ctx, 'argv.log'), new RegExp(SECRET));
});

test('otp on an entry with no TOTP code says so and copies nothing', async (t) => {
  const ctx = scratch(t);
  seed(ctx, 'plain', 'pw\n');
  seed(ctx, 'counter', `pw\notpauth://hotp/X:y?secret=${SECRET}&counter=1\n`);
  for (const name of ['plain', 'counter']) {
    const r = await run(ctx, ['otp', name]);
    assert.notEqual(r.code, 0);
    assert.match(r.stderr, /^dots-pass: no totp code in /);
  }
  assert.equal(existsSync(join(ctx.rec, 'wl-copy.stdin')), false);
});

test('show prints the first line and records nothing', async (t) => {
  const ctx = scratch(t);
  seed(ctx, 'a', 'first\nsecond\n');
  const r = await run(ctx, ['show', 'a']);
  assert.deepEqual([r.code, r.stdout], [0, 'first\n']);
  assert.equal(state(ctx, 'pass-recent'), null);
});

test('exists answers by the entry file', async (t) => {
  const ctx = scratch(t);
  seed(ctx, 'there', 'pw\n');
  assert.equal((await run(ctx, ['exists', 'there'])).code, 0);
  assert.equal((await run(ctx, ['exists', 'not-there'])).code, 1);
});

test('generate prints that many printable characters and refuses a length outside 8 to 128', async (t) => {
  const ctx = scratch(t);
  const r = await run(ctx, ['generate', '24']);
  assert.equal(r.code, 0);
  assert.match(r.stdout, /^[\x21-\x7e]{24}\n$/);
  assert.match((await run(ctx, ['generate', '128'])).stdout, /^[\x21-\x7e]{128}\n$/);
  for (const bad of ['7', '129', 'abc']) assert.equal((await run(ctx, ['generate', bad])).code, 2, bad);
});

test('insert stores the line, records the use and pushes a commit naming the entry', async (t) => {
  const ctx = scratch(t);
  const r = await run(ctx, ['insert', 'web/linear.app'], { input: 'new-pw\n' });
  assert.equal(r.code, 0, r.stderr);
  assert.equal(show(ctx, 'web/linear.app'), 'new-pw\n');
  assert.equal(state(ctx, 'pass-recent'), 'web/linear.app\n');
  assert.match(lastRemote(ctx), /web\/linear\.app/);
});

test('insert refuses an existing entry and leaves it and the remote alone', async (t) => {
  const ctx = scratch(t);
  seed(ctx, 'web/linear.app', 'old\n');
  const remote = lastRemote(ctx);
  const r = await run(ctx, ['insert', 'web/linear.app'], { input: 'new-pw\n' });
  assert.equal(r.code, 1);
  assert.equal(r.stderr, 'dots-pass: web/linear.app exists\n');
  assert.equal(show(ctx, 'web/linear.app'), 'old\n');
  assert.equal(lastRemote(ctx), remote);
});

test('delete removes the entry, forgets its use and otp tag, and pushes', async (t) => {
  const ctx = scratch(t);
  seed(ctx, 'web/gone', 'pw\n');
  seed(ctx, 'web/kept', 'pw\n');
  mkdirSync(ctx.state, { recursive: true });
  writeFileSync(join(ctx.state, 'pass-recent'), 'web/gone\nweb/kept\n');
  writeFileSync(join(ctx.state, 'pass-otp'), 'web/kept\nweb/gone\n');
  const r = await run(ctx, ['delete', 'web/gone']);
  assert.equal(r.code, 0, r.stderr);
  assert.equal((await run(ctx, ['exists', 'web/gone'])).code, 1);
  assert.equal(state(ctx, 'pass-recent'), 'web/kept\n');
  assert.equal(state(ctx, 'pass-otp'), 'web/kept\n');
  assert.match(lastRemote(ctx), /web\/gone/);
});

test('a remote that refuses the push keeps the change and exits 3', async (t) => {
  const ctx = scratch(t);
  const hook = join(ctx.root, 'remote.git', 'hooks', 'pre-receive');
  writeFileSync(hook, '#!/bin/sh\nexit 1\n');
  chmodSync(hook, 0o755);
  const r = await run(ctx, ['insert', 'kept'], { input: 'pw\n' });
  assert.equal(r.code, 3);
  assert.equal(r.stderr, 'dots-pass: saved, not pushed\n');
  assert.equal(show(ctx, 'kept'), 'pw\n');
});

test('a store with no remote saves and exits 0', async (t) => {
  const ctx = scratch(t);
  execFileSync('/usr/bin/pass', ['git', 'remote', 'remove', 'origin'], { env: ctx.env });
  const r = await run(ctx, ['insert', 'local'], { input: 'pw\n' });
  assert.deepEqual([r.code, r.stderr], [0, '']);
  assert.equal(show(ctx, 'local'), 'pw\n');
});

test('edit runs pass edit with kak inside the foot window, then pushes', async (t) => {
  const ctx = scratch(t);
  seed(ctx, 'web/e', 'pw\n');
  const r = await run(ctx, ['edit', 'web/e']);
  assert.equal(r.code, 0, r.stderr);
  assert.match(rec(ctx, 'argv.log'), /^dots-foot /m);
  assert.equal(show(ctx, 'web/e'), 'pw\nedited in kak\n');
  assert.equal(lastRemote(ctx), 'Edit password for web/e using kak.');
});

test('qr-scan names the code from the clipboard image and never shows the secret', async (t) => {
  const ctx = scratch(t);
  qr(ctx, URI);
  const r = await run(ctx, ['qr-scan']);
  assert.equal(r.code, 0, r.stderr);
  assert.equal(r.stdout, 'GitHub\tsaiful\tTOTP\t6\t30\n');
  assert.equal(r.stderr, '');
  assert.doesNotMatch(rec(ctx, 'argv.log'), new RegExp(SECRET));
});

test('qr-scan decodes the label, and reads digits and period, for an hotp code', async (t) => {
  const ctx = scratch(t);
  qr(ctx, 'otpauth://hotp/Acme%20Co:me%40x.io?secret=ABC234&digits=8&period=60');
  assert.equal((await run(ctx, ['qr-scan'])).stdout, 'Acme Co\tme@x.io\tHOTP\t8\t60\n');
});

test('qr-scan refuses a QR that is not an otpauth code and a clipboard with no image', async (t) => {
  const ctx = scratch(t);
  assert.equal((await run(ctx, ['qr-scan'])).code, 1);
  qr(ctx, 'https://example.com/');
  const r = await run(ctx, ['qr-scan']);
  assert.equal(r.code, 1);
  assert.match(r.stderr, /^dots-pass: [^\n]+\n$/);
  assert.equal(r.stdout, '');
});

test('qr-save inserts a new entry from the clipboard, tags it and pushes', async (t) => {
  const ctx = scratch(t);
  qr(ctx, URI);
  const r = await run(ctx, ['qr-save', 'web/new']);
  assert.equal(r.code, 0, r.stderr);
  // Read before the check below runs pass otp itself, which puts the secret in oathtool's argv.
  assert.doesNotMatch(rec(ctx, 'argv.log'), new RegExp(SECRET));
  assert.doesNotMatch(r.stdout + r.stderr, new RegExp(SECRET));
  const code = execFileSync('/usr/bin/pass', ['otp', '--', 'web/new'], { env: ctx.env, encoding: 'utf8' }).trim();
  assert.match(code, /^\d{6}$/);
  assert.equal(state(ctx, 'pass-otp'), 'web/new\n');
  assert.equal(state(ctx, 'pass-recent'), 'web/new\n');
  assert.match(lastRemote(ctx), /web\/new/);
});

test('qr-save appends the code to an entry that exists and keeps its password', async (t) => {
  const ctx = scratch(t);
  seed(ctx, 'web/old', 'keep-me\n');
  qr(ctx, URI);
  const r = await run(ctx, ['qr-save', 'web/old']);
  assert.equal(r.code, 0, r.stderr);
  assert.match(show(ctx, 'web/old'), /^keep-me\n/);
  assert.match(execFileSync('/usr/bin/pass', ['otp', '--', 'web/old'], { env: ctx.env, encoding: 'utf8' }), /^\d{6}\n$/);
  assert.match(lastRemote(ctx), /web\/old/);
});

test('qr-save with no otpauth code writes nothing', async (t) => {
  const ctx = scratch(t);
  qr(ctx, 'https://example.com/');
  assert.equal((await run(ctx, ['qr-save', 'web/none'])).code, 1);
  assert.equal((await run(ctx, ['exists', 'web/none'])).code, 1);
});
