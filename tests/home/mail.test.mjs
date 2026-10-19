// The mail configs render only where the chezmoi age key exists: a keyless apply writes none and still exits 0, a keyed one writes all three.
import { before, after, test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { cpSync, existsSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const repo = new URL('../../', import.meta.url).pathname.replace(/\/$/, '');
const scripts = ['bin/mail-sync', 'bin/hey-folder-sync', 'home/dot_config/notmuch/hooks/executable_post-new'];
const address = 'test@example.com';

let root;

const run = (cmd, args, opts = {}) => spawnSync(cmd, args, { encoding: 'utf8', ...opts });
const has = (tool) => run('sh', ['-c', `command -v ${tool}`]).status === 0;

const scratchHome = (name) => {
  const home = join(root, name);
  mkdirSync(join(home, '.config/chezmoi'), { recursive: true });
  return home;
};

// The scratch config comes from the repo's own config template, so its age block is what the apply uses.
function apply(home, source) {
  const env = { PATH: process.env.PATH, HOME: home, XDG_CONFIG_HOME: join(home, '.config') };
  const config = `${home}.toml`;
  const init = run('chezmoi', ['init', '--source', repo, '--config', config, '--destination', home, '--promptString', 'machine=test'], { env });
  assert.equal(init.status, 0, init.stderr);
  return run('chezmoi', ['--config', config, '--source', source, '--destination', home, 'apply', '--exclude', 'scripts'], { env });
}

let keyless, keyed, porcelainBefore, porcelainAfter;

before(() => {
  root = realpathSync(mkdtempSync(join(tmpdir(), 'mail-')));
  porcelainBefore = run('git', ['-C', repo, 'status', '--porcelain']).stdout;

  keyless = { home: scratchHome('keyless') };
  keyless.result = apply(keyless.home, join(repo, 'home'));

  const src = join(root, 'src');
  cpSync(join(repo, 'home'), src, { recursive: true });
  keyed = { home: scratchHome('keyed') };
  const key = join(keyed.home, '.config/chezmoi/key.txt');
  assert.equal(run('age-keygen', ['-o', key]).status, 0);
  const recipient = run('age-keygen', ['-y', key]).stdout.trim();
  const plain = join(root, 'identities.toml');
  writeFileSync(plain, `primary = "${address}"\nothers = ["a@example.org", "b@example.net"]\n`);
  const enc = run('age', ['-a', '-r', recipient, '-o', join(src, '.chezmoitemplates/mail-identities.toml.age'), plain]);
  assert.equal(enc.status, 0, enc.stderr);
  keyed.result = apply(keyed.home, src);

  porcelainAfter = run('git', ['-C', repo, 'status', '--porcelain']).stdout;
});

after(() => rmSync(root, { recursive: true, force: true }));

test('a keyless apply exits 0 and writes no mail config', () => {
  assert.equal(keyless.result.status, 0, keyless.result.stderr);
  for (const f of ['.mbsyncrc', '.msmtprc', '.config/notmuch/default/config']) {
    assert.equal(existsSync(join(keyless.home, f)), false, f);
  }
});

test('the mail-sync service and timer are in place and both wait for ~/.mbsyncrc', () => {
  for (const unit of ['mail-sync.service', 'mail-sync.timer']) {
    const text = readFileSync(join(keyless.home, '.config/systemd/user', unit), 'utf8');
    assert.match(text, /^ConditionPathExists=%h\/\.mbsyncrc$/m, unit);
  }
});

test('niri starts the mail-sync timer at login', () => {
  const niri = readFileSync(join(keyless.home, '.config/niri/config.kdl'), 'utf8');
  assert.match(niri, /^spawn-at-startup "systemctl" "--user" "start" "mail-sync\.timer"$/m);
});

test('a keyed apply writes all three configs, private, naming the identities', () => {
  assert.equal(keyed.result.status, 0, keyed.result.stderr);
  assert.equal(keyed.result.stderr, '');
  const mbsyncrc = join(keyed.home, '.mbsyncrc');
  assert.equal(statSync(mbsyncrc).mode & 0o777, 0o600);
  assert.match(readFileSync(mbsyncrc, 'utf8'), /^User test@example\.com$/m);
  const msmtprc = join(keyed.home, '.msmtprc');
  assert.equal(statSync(msmtprc).mode & 0o777, 0o600);
  assert.match(readFileSync(msmtprc, 'utf8'), /^from\s+test@example\.com$/m);
  const notmuch = readFileSync(join(keyed.home, '.config/notmuch/default/config'), 'utf8');
  assert.match(notmuch, /^primary_email=test@example\.com$/m);
  assert.match(notmuch, /^other_email=a@example\.org;b@example\.net$/m);
});

test('neither apply changes the repo checkout', () => {
  assert.equal(porcelainAfter, porcelainBefore);
});

test('every carried script parses', () => {
  for (const s of scripts) {
    const r = run('bash', ['-n', join(repo, s)]);
    assert.equal(r.status, 0, `${s}: ${r.stderr}`);
  }
});

test('msmtp reads the rendered config', { skip: !has('msmtp') && 'msmtp is not installed' }, () => {
  const r = run('msmtp', ['-C', join(keyed.home, '.msmtprc'), '-a', 'icloud', '--passwordeval=echo stub', '-P'], { env: { PATH: process.env.PATH, HOME: keyed.home } });
  assert.equal(r.status, 0, r.stderr);
  assert.match(r.stdout, /^host = smtp\.mail\.me\.com$/m);
});

test('notmuch reads the rendered config', { skip: !has('notmuch') && 'notmuch is not installed' }, () => {
  const config = join(keyed.home, '.config/notmuch/default/config');
  const r = run('notmuch', ['config', 'get', 'user.primary_email'], { env: { PATH: process.env.PATH, HOME: keyed.home, NOTMUCH_CONFIG: config } });
  assert.equal(r.status, 0, r.stderr);
  assert.equal(r.stdout, `${address}\n`);
});
