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
  assert.match(s.error, /^conflict: ~\/\.ssh changed here and on a since the last sync; run dots sync --adopt local or --adopt remote$/);

  await ok(b, ['--adopt', 'remote']);
  assert.deepEqual(tree(b), tree(a));
  assert.equal(readFileSync(join(sshDir(b), 'known_hosts'), 'utf8'), 'hosts seen by b\n');
  await ok(b);
  assert.equal(status(b).ssh.ok, true);
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
