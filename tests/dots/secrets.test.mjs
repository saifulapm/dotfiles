// dots secrets on a fresh scratch machine: fake iCloud and Dropbox alias remotes, a test age key, GPG key, ssh blob and pass repo.
import { after, before, test } from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { copyFileSync, existsSync, lstatSync, mkdirSync, readdirSync, readFileSync, statSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { home, must, run, scratch, secrets } from './secrets-lib.mjs';

const repo = new URL('../..', import.meta.url).pathname;
const KEY = '-----BEGIN OPENSSH PRIVATE KEY-----\nsecrets-test-key\n-----END OPENSSH PRIVATE KEY-----\n';
const PASS = {
  'github/cli-token': 'ghp_personal_test',
  'github/cli-token-lareysbd': 'ghp_lareys_test',
  'AI/context7/main': 'ctx7sk-test',
  'workflow/hub-peer-token': 'peer-test',
  'workflow/slack-bot-token': 'xoxb-test',
};

let w;

// iCloud holds dropbox.conf, the age key and the GPG export; Dropbox holds the ssh blob a seeding machine pushed; the pass repo is a local clone source.
async function world() {
  const root = scratch();
  const icloud = join(root, 'icloud');
  const dropbox = join(root, 'dropbox');
  for (const d of ['rclone', 'chezmoi', 'GPG-Backup']) mkdirSync(join(icloud, d), { recursive: true });
  mkdirSync(dropbox);
  writeFileSync(join(icloud, 'rclone/dropbox.conf'), `[Dropbox]\ntype = alias\nremote = ${dropbox}\n`);

  const fixture = home(root, 'fixture', '');
  await must(fixture, 'age-keygen', ['-o', join(icloud, 'chezmoi/key.txt')]);
  await must(fixture, 'gpg', ['--batch', '--passphrase', '', '--quick-gen-key', 'secrets test <t@example.invalid>', 'future-default', 'default', 'never']);
  const fpr = (await must(fixture, 'gpg', ['--with-colons', '--list-secret-keys'])).match(/^fpr:+([0-9A-F]+):/m)[1];
  writeFileSync(join(icloud, 'GPG-Backup/gpg-secret-test.asc'), await must(fixture, 'gpg', ['--batch', '--armor', '--export-secret-keys', fpr]));

  const store = { ...fixture, PASSWORD_STORE_DIR: join(root, 'password-store') };
  await must(store, 'pass', ['init', fpr]);
  await must(store, 'pass', ['git', 'init']);
  for (const [entry, value] of Object.entries(PASS)) await must(store, 'pass', ['insert', '-m', entry], value + '\n');

  const seed = home(root, 'seed', `[Dropbox]\ntype = alias\nremote = ${dropbox}\n`);
  mkdirSync(join(seed.XDG_CONFIG_HOME, 'chezmoi'));
  copyFileSync(join(icloud, 'chezmoi/key.txt'), join(seed.XDG_CONFIG_HOME, 'chezmoi/key.txt'));
  mkdirSync(join(seed.HOME, '.ssh'), { mode: 0o700 });
  writeFileSync(join(seed.HOME, '.ssh/id_ed25519'), KEY, { mode: 0o600 });
  writeFileSync(join(seed.HOME, '.ssh/id_ed25519.pub'), 'ssh-ed25519 AAAA test\n', { mode: 0o644 });
  writeFileSync(join(seed.HOME, '.ssh/config'), 'Host nuc\n', { mode: 0o600 });
  await must(seed, new URL('../../bin/dots', import.meta.url).pathname, ['sync', '--only', 'ssh']);

  const conf = `[iCloud]\ntype = alias\nremote = ${icloud}\n`;
  const m = { ...home(root, 'fresh', conf), DOTS_PASS_REPO: store.PASSWORD_STORE_DIR };
  return { root, icloud, dropbox, fpr, conf, fixture, seed, m };
}

// Path, size, mtime and sha256 of every file under dir.
function snapshot(dir, out = {}) {
  for (const name of readdirSync(dir)) {
    const p = join(dir, name);
    const s = lstatSync(p);
    if (s.isDirectory()) snapshot(p, out);
    else if (s.isFile()) out[p] = [s.size, s.mtimeMs, createHash('sha256').update(readFileSync(p)).digest('hex')];
  }
  return out;
}

const porcelain = () => must({ ...w.m }, 'git', ['-C', repo, 'status', '--porcelain']);
const mode = (p) => (statSync(p).mode & 0o777).toString(8);
const gh = (args) => must(w.m, 'gh', args);

let dirtyBefore;
let first;

before(async () => {
  w = await world();
  dirtyBefore = await porcelain();
  first = await secrets(w.m);
});

after(async () => {
  for (const env of [w.fixture, w.m]) await run(env, 'gpgconf', ['--kill', 'gpg-agent']);
});

test('with no iCloud: remote it exits 1 and names rclone config as the next step', async () => {
  const bare = home(w.root, 'bare', `[Other]\ntype = alias\nremote = ${w.root}\n`);
  const r = await secrets(bare);
  assert.equal(r.code, 1, r.stdout + r.stderr);
  assert.match(r.stdout + r.stderr, /rclone config/);
});

test('a fresh machine gets the Dropbox remote, age key, ~/.ssh, GPG key, pass store and gh tokens', async () => {
  assert.equal(first.code, 0, first.stdout + first.stderr);
  const { m } = w;

  assert.equal(readFileSync(m.RCLONE_CONFIG, 'utf8'), `${w.conf}[Dropbox]\ntype = alias\nremote = ${w.dropbox}\n`);

  const key = join(m.XDG_CONFIG_HOME, 'chezmoi/key.txt');
  assert.equal(readFileSync(key, 'utf8'), readFileSync(join(w.icloud, 'chezmoi/key.txt'), 'utf8'));
  assert.equal(mode(key), '600');

  const ssh = join(m.HOME, '.ssh');
  assert.deepEqual(readdirSync(ssh).sort(), ['config', 'id_ed25519', 'id_ed25519.pub']);
  assert.equal(readFileSync(join(ssh, 'id_ed25519'), 'utf8'), KEY);
  assert.equal(mode(join(ssh, 'id_ed25519')), '600');

  assert.match(await must(m, 'gpg', ['--with-colons', '--list-secret-keys']), new RegExp(`^fpr:+${w.fpr}:`, 'm'));
  assert.match(await must(m, 'gpg', ['--export-ownertrust']), new RegExp(`^${w.fpr}:6:$`, 'm'));

  assert.ok(existsSync(join(m.HOME, '.password-store/.git')));
  assert.equal(await must(m, 'pass', ['show', 'github/cli-token']), 'ghp_personal_test\n');

  assert.equal(await gh(['auth', 'token', '--hostname', 'github.com', '--user', 'saifulapm']), 'ghp_personal_test\n');
  assert.equal(await gh(['auth', 'token', '--hostname', 'github.com', '--user', 'lareysbd']), 'ghp_lareys_test\n');
  const status = await run(m, 'gh', ['auth', 'status']);
  assert.match(status.stdout + status.stderr, /account saifulapm/);
  assert.match(status.stdout + status.stderr, /account lareysbd/);
  assert.equal(mode(join(m.GH_CONFIG_DIR, 'hosts.yml')), '600');

  const ctx7 = join(m.XDG_CONFIG_HOME, 'context7/credentials.json');
  assert.equal(readFileSync(ctx7, 'utf8'), '{\n  "access_token": "ctx7sk-test",\n  "token_type": "Bearer"\n}\n');
  assert.equal(mode(ctx7), '600');
  const env = join(m.XDG_CONFIG_HOME, 'hub/local.env');
  assert.equal(readFileSync(env, 'utf8'), 'HUB_PEER_TOKEN=peer-test\nSLACK_BOT_TOKEN=xoxb-test\n');
  assert.equal(mode(env), '600');
});

test('a second run changes no file in the scratch home', async () => {
  const beforeRun = snapshot(w.m.HOME);
  const r = await secrets(w.m);
  assert.equal(r.code, 0, r.stdout + r.stderr);
  assert.deepEqual(snapshot(w.m.HOME), beforeRun);
});

test('nothing is written into the repo checkout', async () => {
  assert.equal(await porcelain(), dirtyBefore);
});

for (const [what, extra] of [
  ['an indented [iCloud] section', ' [iCloud]\ntype = alias\nremote = /tmp/evil\n'],
  ['a second section of any name', '[Other]\ntype = alias\nremote = /etc\n'],
]) {
  test(`a dropbox.conf carrying ${what} is refused and the rclone config left alone`, async () => {
    const forged = join(w.root, `forged-${extra.length}`);
    mkdirSync(join(forged, 'rclone'), { recursive: true });
    writeFileSync(join(forged, 'rclone/dropbox.conf'), `[Dropbox]\ntype = alias\nremote = ${w.dropbox}\n${extra}`);
    const conf = `[iCloud]\ntype = alias\nremote = ${forged}\n`;
    const m = home(w.root, `forged-home-${extra.length}`, conf);
    const r = await secrets(m);
    assert.equal(r.code, 1, r.stdout + r.stderr);
    assert.match(r.stderr, /dropbox\.conf/);
    assert.equal(readFileSync(m.RCLONE_CONFIG, 'utf8'), conf);
  });
}

test('a machine that already holds every secret runs on while iCloud is unreachable', async () => {
  const conf = readFileSync(w.m.RCLONE_CONFIG, 'utf8');
  writeFileSync(w.m.RCLONE_CONFIG, conf.replace(`remote = ${w.icloud}\n`, `remote = ${join(w.root, 'expired')}\n`));
  try {
    const r = await secrets(w.m);
    assert.equal(r.code, 0, r.stdout + r.stderr);
  } finally {
    writeFileSync(w.m.RCLONE_CONFIG, conf);
  }
});

test('a fresh machine with iCloud unreachable stops and names rclone config reconnect', async () => {
  const m = home(w.root, 'expired-home', `[iCloud]\ntype = alias\nremote = ${join(w.root, 'expired')}\n`);
  const r = await secrets(m);
  assert.equal(r.code, 1, r.stdout + r.stderr);
  assert.match(r.stderr, /rclone config reconnect iCloud:/);
});

// A machine first reached over ssh: no base, and a ~/.ssh holding only authorized_keys; its Dropbox: holds a blob with its own authorized_keys.
test('a machine reached over ssh restores ~/.ssh with both sides of authorized_keys and gets past the pass clone', async () => {
  const dropbox = join(w.root, 'reach-dropbox');
  mkdirSync(dropbox);
  const remote = `[Dropbox]\ntype = alias\nremote = ${dropbox}\n`;
  const seed = home(w.root, 'reach-seed', remote);
  mkdirSync(join(seed.XDG_CONFIG_HOME, 'chezmoi'));
  copyFileSync(join(w.icloud, 'chezmoi/key.txt'), join(seed.XDG_CONFIG_HOME, 'chezmoi/key.txt'));
  mkdirSync(join(seed.HOME, '.ssh'), { mode: 0o700 });
  writeFileSync(join(seed.HOME, '.ssh/id_ed25519'), KEY, { mode: 0o600 });
  writeFileSync(join(seed.HOME, '.ssh/authorized_keys'), 'ssh-ed25519 BBBB shared\n', { mode: 0o600 });
  await must(seed, new URL('../../bin/dots', import.meta.url).pathname, ['sync', '--only', 'ssh']);

  const m = { ...home(w.root, 'reached', w.conf + remote), DOTS_PASS_REPO: w.m.DOTS_PASS_REPO };
  mkdirSync(join(m.HOME, '.ssh'), { mode: 0o700 });
  writeFileSync(join(m.HOME, '.ssh/authorized_keys'), 'ssh-ed25519 AAAA reach\n', { mode: 0o600 });
  try {
    const r = await secrets(m);
    assert.equal(r.code, 0, r.stdout + r.stderr);
    assert.match(r.stdout, /^dots: ~\/\.ssh restored$/m);
    assert.match(r.stdout, /^dots: password store cloned$/m);
    assert.equal(readFileSync(join(m.HOME, '.ssh/id_ed25519'), 'utf8'), KEY);
    assert.equal(readFileSync(join(m.HOME, '.ssh/authorized_keys'), 'utf8'), 'ssh-ed25519 BBBB shared\nssh-ed25519 AAAA reach\n');
  } finally {
    await run(m, 'gpgconf', ['--kill', 'gpg-agent']);
  }
});

test('with a recorded ssh base it fetches nothing for ~/.ssh, even when ~/.ssh holds only known_hosts', async () => {
  const m = { ...home(w.root, 'based', w.conf), DOTS_PASS_REPO: w.m.DOTS_PASS_REPO };
  const state = join(m.XDG_STATE_HOME, 'dots/sync/ssh');
  mkdirSync(state, { recursive: true });
  writeFileSync(join(state, 'base.hash'), JSON.parse(readFileSync(join(w.dropbox, 'qshell-sync/ssh/ssh.meta.json'), 'utf8')).hash + '\n');
  mkdirSync(join(m.HOME, '.ssh'), { mode: 0o700 });
  writeFileSync(join(m.HOME, '.ssh/known_hosts'), 'hosts seen here\n');
  try {
    const r = await secrets(m);
    assert.equal(r.code, 0, r.stdout + r.stderr);
    assert.doesNotMatch(r.stdout, /~\/\.ssh restored/);
    assert.deepEqual(readdirSync(join(m.HOME, '.ssh')), ['known_hosts']);
  } finally {
    await run(m, 'gpgconf', ['--kill', 'gpg-agent']);
  }
});

test('with no base and an id_ed25519 that differs from the blob, it stops on the ssh conflict and leaves ~/.ssh alone', async () => {
  const m = home(w.root, 'differs', w.conf);
  mkdirSync(join(m.HOME, '.ssh'), { mode: 0o700 });
  writeFileSync(join(m.HOME, '.ssh/id_ed25519'), 'another key\n', { mode: 0o600 });
  const r = await secrets(m);
  assert.equal(r.code, 1, r.stdout + r.stderr);
  assert.match(r.stderr, /conflict, run dots sync --adopt local or remote/);
  assert.deepEqual(readdirSync(join(m.HOME, '.ssh')), ['id_ed25519']);
  assert.equal(readFileSync(join(m.HOME, '.ssh/id_ed25519'), 'utf8'), 'another key\n');
});
