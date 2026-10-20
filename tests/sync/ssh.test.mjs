// ~/.ssh travels as v1's age blob under qshell-sync/ssh, with a three-way rule that stops when both sides changed.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { chmodSync, existsSync, mkdirSync, readdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { identity, machine, sync, world } from './lib.mjs';

const KEY = '-----BEGIN OPENSSH PRIVATE KEY-----\nmarker-only-in-the-key\n-----END OPENSSH PRIVATE KEY-----\n';

const sshDir = (m) => join(m.env.HOME, '.ssh');
function put(m, name, text, mode = 0o600) {
  mkdirSync(sshDir(m), { recursive: true, mode: 0o700 });
  writeFileSync(join(sshDir(m), name), text);
  chmodSync(join(sshDir(m), name), mode);
}
// Every file in m's ~/.ssh with its content, known_hosts left out unless asked for.
function tree(m, all = false) {
  const files = {};
  for (const f of readdirSync(sshDir(m)).sort()) if (all || !f.startsWith('known_hosts')) files[f] = readFileSync(join(sshDir(m), f), 'utf8');
  return files;
}
const blob = (w) => ['ssh.age', 'ssh.meta.json'].map((f) => readFileSync(join(w.remote, 'qshell-sync/ssh', f)));
const status = (m) => JSON.parse(readFileSync(m.status, 'utf8'));

async function ok(m, args) {
  const r = await sync(m, args);
  assert.equal(r.code, 0, `dots sync ${args ?? ''} on ${m.id} exited ${r.code}: ${r.stdout}${r.stderr}`);
}

// a seeds the remote and b pulls it, so both share one agreed base.
async function agreed() {
  const w = world();
  const [a, b] = [machine(w, 'a'), machine(w, 'b')];
  await identity(a);
  await identity(b, a);
  put(a, 'id_ed25519', KEY);
  put(a, 'id_ed25519.pub', 'ssh-ed25519 AAAA a\n', 0o644);
  put(a, 'known_hosts', 'hosts seen by a\n', 0o644);
  put(b, 'known_hosts', 'hosts seen by b\n', 0o644);
  await ok(a, ['--only', 'ssh']);
  await ok(b, ['--only', 'ssh']);
  return { w, a, b };
}

test('an empty ~/.ssh pulls the shared keys and keeps its own known_hosts', async () => {
  const { a, b } = await agreed();
  assert.deepEqual(tree(b), tree(a));
  assert.equal(readFileSync(join(sshDir(b), 'known_hosts'), 'utf8'), 'hosts seen by b\n');
});

test('the remote blob is age-encrypted, and a new machine c with no ~/.ssh pulls it', async () => {
  const { w, a } = await agreed();
  const [age] = blob(w);
  assert.equal(age.subarray(0, 21).toString(), 'age-encryption.org/v1');
  assert.equal(age.includes('marker-only-in-the-key'), false);
  const c = machine(w, 'c');
  await identity(c, a);
  await ok(c, ['--only', 'ssh']);
  assert.deepEqual(tree(c), tree(a));
});

test('with ~/.ssh changed on both sides, b stops with exit 3 and changes neither, then --adopt remote settles it', async () => {
  const { w, a, b } = await agreed();
  put(a, 'config', 'Host nuc\n');
  await ok(a, ['--only', 'ssh']);
  put(b, 'config', 'Host mac\n');
  const before = { mine: tree(b, true), remote: blob(w) };
  const r = await sync(b, ['--only', 'ssh']);
  assert.equal(r.code, 3, r.stdout + r.stderr);
  assert.deepEqual(tree(b, true), before.mine);
  assert.deepEqual(blob(w), before.remote);
  const s = status(b).ssh;
  assert.equal(s.ok, false);
  assert.match(s.error, /^conflict, run dots sync --adopt local or remote: ~\/\.ssh changed here and on a since the last sync$/);
  // Route cuts an error at 60 characters, so the fix comes first.
  assert.match(s.error.slice(0, 59), /--adopt local or remote/);

  await ok(b, ['--adopt', 'remote']);
  assert.deepEqual(tree(b), tree(a));
  assert.equal(readFileSync(join(sshDir(b), 'known_hosts'), 'utf8'), 'hosts seen by b\n');
  await ok(b);
  assert.equal(status(b).ssh.ok, true);
});

test('when another machine pushes right after a, a does not take its own push as agreed, and its next round stops', async () => {
  const { w, a } = await agreed();
  put(a, 'config', 'Host nuc\n');
  await ok(machine(w, 'a', { racer: true }), ['--only', 'ssh']);
  const r = await sync(a, ['--only', 'ssh']);
  assert.equal(r.code, 3, r.stdout + r.stderr);
  assert.equal(readFileSync(join(sshDir(a), 'config'), 'utf8'), 'Host nuc\n');
});

test('DOTS_AGE_IDENTITY names the key, so a missing one skips the ssh unit even when key.txt exists', async () => {
  const w = world();
  const a = machine(w, 'a');
  await identity(a);
  put(a, 'id_ed25519', KEY);
  a.env.DOTS_AGE_IDENTITY = join(a.env.HOME, 'no-such-key');
  await ok(a, ['--only', 'ssh']);
  assert.equal(existsSync(join(w.remote, 'qshell-sync/ssh/ssh.age')), false);
  assert.equal(status(a).ssh.ok, true);
});

const base = (m) => readFileSync(join(m.env.XDG_STATE_HOME, 'dots/sync/ssh/base.hash'), 'utf8').trim();
const meta = (w) => JSON.parse(readFileSync(join(w.remote, 'qshell-sync/ssh/ssh.meta.json'), 'utf8'));

// c is a machine first reached over ssh: no base, and a ~/.ssh holding only authorized_keys beside its own known_hosts.
async function reached(w, a, keys) {
  const c = machine(w, 'c');
  await identity(c, a);
  put(c, 'authorized_keys', keys);
  put(c, 'known_hosts', 'hosts seen by c\n', 0o644);
  await ok(c, ['--only', 'ssh']);
  return c;
}

test('a ~/.ssh holding only authorized_keys keeps its lines on the first pull, and the next round pushes the union', async () => {
  const { w, a } = await agreed();
  put(a, 'authorized_keys', 'ssh-ed25519 BBBB shared\nssh-ed25519 CCCC both\n');
  await ok(a, ['--only', 'ssh']);
  const c = await reached(w, a, 'ssh-ed25519 AAAA reach\nssh-ed25519 CCCC both\n');
  assert.equal(tree(c).id_ed25519, KEY);
  assert.equal(tree(c).authorized_keys, 'ssh-ed25519 BBBB shared\nssh-ed25519 CCCC both\nssh-ed25519 AAAA reach\n');
  assert.equal(readFileSync(join(sshDir(c), 'known_hosts'), 'utf8'), 'hosts seen by c\n');

  await ok(c);
  assert.equal(status(c).ssh.ok, true);
  assert.equal(status(c).ssh.error, null);
  assert.equal(meta(w).machine, 'c');
  assert.equal(meta(w).hash, base(c));
  await ok(a, ['--only', 'ssh']);
  assert.equal(tree(a).authorized_keys, 'ssh-ed25519 BBBB shared\nssh-ed25519 CCCC both\nssh-ed25519 AAAA reach\n');

  // Once c has a base, a pull mirrors the blob, so a key a removes is gone from c too.
  put(a, 'authorized_keys', 'ssh-ed25519 CCCC both\nssh-ed25519 AAAA reach\n');
  await ok(a, ['--only', 'ssh']);
  await ok(c, ['--only', 'ssh']);
  assert.equal(tree(c).authorized_keys, 'ssh-ed25519 CCCC both\nssh-ed25519 AAAA reach\n');
});

test('a blob with no authorized_keys leaves the local one byte for byte on the first pull', async () => {
  const { w, a } = await agreed();
  const c = await reached(w, a, 'ssh-ed25519 AAAA reach\n\nssh-rsa ZZZZ no newline');
  assert.equal(tree(c).id_ed25519, KEY);
  assert.equal(tree(c).authorized_keys, 'ssh-ed25519 AAAA reach\n\nssh-rsa ZZZZ no newline');
});

test('with no base and a ~/.ssh holding its own id_ed25519 beside authorized_keys, the pull still stops as a conflict', async () => {
  const { w, a } = await agreed();
  const c = machine(w, 'c');
  await identity(c, a);
  put(c, 'id_ed25519', 'another key\n');
  put(c, 'authorized_keys', 'ssh-ed25519 AAAA reach\n');
  const before = { mine: tree(c, true), remote: blob(w) };
  const r = await sync(c, ['--only', 'ssh']);
  assert.equal(r.code, 3, r.stdout + r.stderr);
  assert.match(r.stderr, /conflict, run dots sync --adopt local or remote: ~\/\.ssh here was never synced/);
  assert.deepEqual(tree(c, true), before.mine);
  assert.deepEqual(blob(w), before.remote);
});
