// dekho's TMDB key renders only where the chezmoi age key exists: a keyless apply writes no ~/.config/dekho/config.toml, a keyed one writes it private.
import { before, after, test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { cpSync, existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, realpathSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const repo = new URL('../../', import.meta.url).pathname.replace(/\/$/, '');
const run = (cmd, args, opts = {}) => spawnSync(cmd, args, { encoding: 'utf8', ...opts });

let root, keyless, keyed;

function sealOthers(src, recipient, own) {
  const empty = join(root, 'empty.toml');
  writeFileSync(empty, '');
  for (const blob of readdirSync(join(src, '.chezmoitemplates')).filter((f) => f.endsWith('.age') && f !== own)) {
    const r = run('age', ['-a', '-r', recipient, '-o', join(src, '.chezmoitemplates', blob), empty]);
    assert.equal(r.status, 0, r.stderr);
  }
}

const scratchHome = (name) => {
  const home = join(root, name);
  mkdirSync(join(home, '.config/chezmoi'), { recursive: true });
  return home;
};

function apply(home, source) {
  const env = { PATH: process.env.PATH, HOME: home, XDG_CONFIG_HOME: join(home, '.config') };
  const config = `${home}.toml`;
  const init = run('chezmoi', ['init', '--source', repo, '--config', config, '--destination', home, '--promptString', 'machine=test'], { env });
  assert.equal(init.status, 0, init.stderr);
  return run('chezmoi', ['--config', config, '--source', source, '--destination', home, 'apply', '--exclude', 'scripts'], { env });
}

before(() => {
  root = realpathSync(mkdtempSync(join(tmpdir(), 'dekho-')));
  keyless = { home: scratchHome('keyless') };
  keyless.result = apply(keyless.home, join(repo, 'home'));

  const src = join(root, 'src');
  cpSync(join(repo, 'home'), src, { recursive: true });
  keyed = { home: scratchHome('keyed') };
  const key = join(keyed.home, '.config/chezmoi/key.txt');
  assert.equal(run('age-keygen', ['-o', key]).status, 0);
  const recipient = run('age-keygen', ['-y', key]).stdout.trim();
  const plain = join(root, 'dekho.toml');
  writeFileSync(plain, 'tmdb_api_key = "test-key-0123"\n');
  const enc = run('age', ['-a', '-r', recipient, '-o', join(src, '.chezmoitemplates/dekho.toml.age'), plain]);
  assert.equal(enc.status, 0, enc.stderr);
  // The keyed apply decrypts every age blob, so each other one is sealed to the scratch key as an empty TOML, a blob added later included.
  sealOthers(src, recipient, 'dekho.toml.age');
  keyed.result = apply(keyed.home, src);
});

after(() => rmSync(root, { recursive: true, force: true }));

test('a keyless apply exits 0 and writes no dekho config', () => {
  assert.equal(keyless.result.status, 0, keyless.result.stderr);
  assert.equal(existsSync(join(keyless.home, '.config/dekho/config.toml')), false);
});

test('a keyed apply writes the TMDB key into a private dekho config', () => {
  assert.equal(keyed.result.status, 0, keyed.result.stderr);
  const config = join(keyed.home, '.config/dekho/config.toml');
  assert.equal(statSync(config).mode & 0o777, 0o600);
  assert.match(readFileSync(config, 'utf8'), /^tmdb_api_key = "test-key-0123"$/m);
});
