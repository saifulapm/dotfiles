// dots context7 in a scratch home, with pass played by a stub that answers from files.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { chmodSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';

const dots = new URL('../../bin/dots', import.meta.url).pathname;
const KEYS = { main: 'ctx7sk-main-test', alt: 'ctx7sk-alt-test' };

function scratch(t) {
  const root = mkdtempSync(join(tmpdir(), 'dots-context7-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const bin = join(root, 'bin');
  const store = join(root, 'store');
  mkdirSync(bin);
  mkdirSync(store);
  for (const [id, key] of Object.entries(KEYS)) writeFileSync(join(store, 'AI-context7-' + id), key + '\nsecond line\n');
  writeFileSync(join(bin, 'pass'), `#!/usr/bin/env bash\nf="$STUB_STORE/\${2//\\//-}"\n[ -e "$f" ] || { echo "Error: $2 is not in the password store." >&2; exit 1; }\ncat "$f"\n`);
  chmodSync(join(bin, 'pass'), 0o755);
  const env = { HOME: join(root, 'home'), XDG_STATE_HOME: join(root, 'state'), XDG_CONFIG_HOME: join(root, 'config'), PATH: `${bin}:${process.env.PATH}`, STUB_STORE: store };
  const run = (...args) => spawnSync(dots, ['context7', ...args], { env, encoding: 'utf8' });
  const creds = join(env.XDG_CONFIG_HOME, 'context7/credentials.json');
  const active = join(env.XDG_STATE_HOME, 'dots/context7-active');
  const login = () => JSON.parse(readFileSync(creds, 'utf8'));
  return { run, creds, active, login };
}

const bearer = (key) => ({ access_token: key, token_type: 'Bearer' });

test('apply with no choice writes the main key, mode 600, as the CLI reads it', (t) => {
  const s = scratch(t);
  const r = s.run('apply');
  assert.equal(r.status, 0, r.stderr);
  assert.equal(readFileSync(s.creds, 'utf8'), '{\n  "access_token": "ctx7sk-main-test",\n  "token_type": "Bearer"\n}\n');
  assert.equal((statSync(s.creds).mode & 0o777).toString(8), '600');
  assert.ok(!existsSync(s.active));
});

test('use makes a key this device’s, and apply after it keeps that key and the file untouched', (t) => {
  const s = scratch(t);
  s.run('apply');
  const r = s.run('use', 'alt');
  assert.equal(r.status, 0, r.stderr);
  assert.deepEqual(s.login(), bearer(KEYS.alt));
  assert.equal(readFileSync(s.active, 'utf8'), 'alt\n');
  const before = statSync(s.creds).mtimeMs;
  assert.equal(s.run('apply').status, 0);
  assert.deepEqual(s.login(), bearer(KEYS.alt));
  assert.equal(statSync(s.creds).mtimeMs, before);
});

test('a key not in pass or an id outside the label alphabet is refused and changes nothing', (t) => {
  const s = scratch(t);
  s.run('use', 'alt');
  for (const id of ['clt', '../main', '', 'Main']) {
    const r = s.run('use', id);
    assert.equal(r.status, 1, id);
    assert.ok(!r.stdout.includes('ctx7sk') && !r.stderr.includes('ctx7sk'), r.stderr);
  }
  assert.deepEqual(s.login(), bearer(KEYS.alt));
  assert.equal(readFileSync(s.active, 'utf8'), 'alt\n');
});

test('a forged choice in the state file is refused, and the login stays', (t) => {
  const s = scratch(t);
  s.run('use', 'alt');
  writeFileSync(s.active, '../../etc/x\n');
  const r = s.run('apply');
  assert.equal(r.status, 1);
  assert.match(r.stderr, /dots context7 use main/);
  assert.deepEqual(s.login(), bearer(KEYS.alt));
});
