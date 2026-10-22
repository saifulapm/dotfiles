// dots claude-account and the fish cx, with claude and its login played by a stub in a scratch home.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { chmodSync, mkdirSync, mkdtempSync, readFileSync, readlinkSync, existsSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { delimiter, join } from 'node:path';
import { spawnSync } from 'node:child_process';

const dots = new URL('../../bin/dots', import.meta.url).pathname;
const cxFn = new URL('../../home/dot_config/fish/functions/cx.fish', import.meta.url).pathname;
const links = ['skills', 'agents', 'settings.json', 'CLAUDE.md', 'history.jsonl', 'projects'];

const stub = `#!/usr/bin/env bash
if [ "$1 $2" = "auth login" ]; then
  [ -z "\${STUB_LOGIN_FAIL:-}" ] || exit 1
  echo "$CLAUDE_CONFIG_DIR|$*" >>"$REC/login.log"
  echo '{"claudeAiOauth":{"accessToken":"sk-ant-oat01-secret","refreshToken":"sk-ant-ort01-secret"}}' >"$CLAUDE_CONFIG_DIR/.credentials.json"
elif [ "$1 $2" = "auth status" ]; then
  if [ -z "\${CLAUDE_CONFIG_DIR:-}" ]; then echo '{"loggedIn":true,"email":"main@example.com","subscriptionType":"max"}'
  else echo "{\\"loggedIn\\":true,\\"email\\":\\"$(basename "$CLAUDE_CONFIG_DIR")@example.com\\",\\"subscriptionType\\":\\"pro\\"}"; fi
else
  echo "dir=\${CLAUDE_CONFIG_DIR:-unset} argv=$*"
fi
`;

function scratch(t) {
  const root = mkdtempSync(join(tmpdir(), 'dots-claude-account-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const home = join(root, 'home');
  const bindir = join(root, 'bin');
  for (const d of ['rec', 'state', 'config', 'cache', 'data', 'run']) mkdirSync(join(root, d));
  for (const d of [bindir, join(home, '.claude')]) mkdirSync(d, { recursive: true });
  writeFileSync(join(bindir, 'claude'), stub);
  chmodSync(join(bindir, 'claude'), 0o755);
  for (const n of ['skills', 'agents', 'projects']) mkdirSync(join(home, '.claude', n));
  for (const n of ['settings.json', 'CLAUDE.md', 'history.jsonl']) writeFileSync(join(home, '.claude', n), '');
  const env = {
    ...process.env,
    HOME: home,
    XDG_CONFIG_HOME: join(root, 'config'),
    XDG_STATE_HOME: join(root, 'state'),
    XDG_CACHE_HOME: join(root, 'cache'),
    XDG_DATA_HOME: join(root, 'data'),
    XDG_RUNTIME_DIR: join(root, 'run'),
    PATH: [bindir, process.env.PATH].join(delimiter),
    REC: join(root, 'rec'),
  };
  delete env.CLAUDE_CONFIG_DIR;
  delete env.STUB_LOGIN_FAIL;
  const reg = join(root, 'state/dots/claude-accounts.json');
  const run = (args, extra = {}) => spawnSync(dots, ['claude-account', ...args], { env: { ...env, ...extra }, encoding: 'utf8' });
  return { root, home, env, reg, run };
}

test('add links the shared entries, records both accounts and holds no token', (t) => {
  const s = scratch(t);
  const r = s.run(['add', 'work']);
  assert.equal(r.status, 0, r.stderr);
  for (const n of links) assert.equal(readlinkSync(join(s.root, 'state/dots/claude-accounts/work', n)), join(s.home, '.claude', n));
  const text = readFileSync(s.reg, 'utf8');
  assert.deepEqual(JSON.parse(text), {
    active: 'main',
    accounts: [
      { id: 'main', label: 'main', home: join(s.home, '.claude'), email: 'main@example.com', plan: 'max' },
      { id: 'work', label: 'work', home: join(s.root, 'state/dots/claude-accounts/work'), email: 'work@example.com', plan: 'pro' },
    ],
  });
  assert.ok(!text.includes('sk-ant'));
  assert.equal(readFileSync(join(s.root, 'rec/login.log'), 'utf8'), `${join(s.root, 'state/dots/claude-accounts/work')}|auth login\n`);
});

test('use switches the active account and an unknown id changes nothing', (t) => {
  const s = scratch(t);
  assert.equal(s.run(['add', 'work']).status, 0);
  assert.equal(s.run(['use', 'work']).status, 0);
  assert.equal(JSON.parse(readFileSync(s.reg, 'utf8')).active, 'work');
  const before = readFileSync(s.reg);
  const r = s.run(['use', 'nope']);
  assert.notEqual(r.status, 0);
  assert.deepEqual(readFileSync(s.reg), before);
});

test('a failed login leaves no registry and no home', (t) => {
  const s = scratch(t);
  const r = s.run(['add', 'work'], { STUB_LOGIN_FAIL: '1' });
  assert.notEqual(r.status, 0);
  assert.equal(existsSync(s.reg), false);
  assert.equal(existsSync(join(s.root, 'state/dots/claude-accounts/work')), false);
});

test('a bad or repeated label is refused', (t) => {
  const s = scratch(t);
  assert.notEqual(s.run(['add', 'Work_1']).status, 0);
  assert.equal(s.run(['add', 'work']).status, 0);
  const before = readFileSync(s.reg);
  assert.notEqual(s.run(['add', 'work']).status, 0);
  assert.notEqual(s.run(['add', 'main']).status, 0);
  assert.deepEqual(readFileSync(s.reg), before);
});

test('cx sets CLAUDE_CONFIG_DIR only for a second active account', (t) => {
  const s = scratch(t);
  const cx = () => spawnSync('fish', ['-c', `source ${cxFn}; cx -p hi`], { env: s.env, encoding: 'utf8' }).stdout.trim();
  assert.equal(cx(), 'dir=unset argv=--allow-dangerously-skip-permissions -p hi');
  assert.equal(s.run(['add', 'work']).status, 0);
  assert.equal(cx(), 'dir=unset argv=--allow-dangerously-skip-permissions -p hi');
  // A home left in the caller's environment does not pick the account; the registry does.
  const inherited = spawnSync('fish', ['-c', `source ${cxFn}; cx -p hi`], { env: Object.assign({}, s.env, { CLAUDE_CONFIG_DIR: '/elsewhere' }), encoding: 'utf8' }).stdout.trim();
  assert.equal(inherited, 'dir=unset argv=--allow-dangerously-skip-permissions -p hi');
  assert.equal(s.run(['use', 'work']).status, 0);
  assert.equal(cx(), `dir=${join(s.root, 'state/dots/claude-accounts/work')} argv=--allow-dangerously-skip-permissions -p hi`);
});
