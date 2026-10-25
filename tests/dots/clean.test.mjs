// dots clean on a scratch home: git repos, agent worktrees and a cache aged with touch, and pnpm, npm, uv and podman played by stubs.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { chmodSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { delimiter, join } from 'node:path';
import { execFileSync, spawnSync } from 'node:child_process';

const dots = new URL('../../bin/dots', import.meta.url).pathname;
const tools = ['pnpm', 'npm', 'uv', 'podman'];

function scratch(t) {
  const root = mkdtempSync(join(tmpdir(), 'dots-clean-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const home = join(root, 'home');
  const bindir = join(root, 'bin');
  const rec = join(root, 'rec.log');
  mkdirSync(bindir);
  mkdirSync(home);
  for (const n of tools) {
    // podman images lists one untagged image; every other call is recorded.
    const body = n === 'podman' ? 'if [ "$1" = images ]; then echo abc123; exit 0; fi\n' : '';
    writeFileSync(join(bindir, n), `#!/usr/bin/env bash\n${body}echo "${n} $*" >>"$REC"\n`);
    chmodSync(join(bindir, n), 0o755);
  }
  const env = {
    ...process.env,
    HOME: home,
    XDG_CACHE_HOME: join(home, '.cache'),
    PATH: [bindir, process.env.PATH].join(delimiter),
    REC: rec,
    GIT_CONFIG_GLOBAL: '/dev/null',
    GIT_AUTHOR_NAME: 't',
    GIT_AUTHOR_EMAIL: 't@example.com',
    GIT_COMMITTER_NAME: 't',
    GIT_COMMITTER_EMAIL: 't@example.com',
  };
  const git = (cwd, ...args) => execFileSync('git', args, { cwd, env, stdio: 'pipe' });
  const file = (path, text = 'x') => {
    mkdirSync(join(path, '..'), { recursive: true });
    writeFileSync(path, text);
  };
  const age = (path) => execFileSync('find', [path, '-exec', 'touch', '-h', '-d', '20 days ago', '{}', '+']);
  const repo = (path, ignore) => {
    mkdirSync(path, { recursive: true });
    git(path, 'init', '-q');
    file(join(path, '.gitignore'), ignore);
    file(join(path, 'README'));
    git(path, 'add', '.');
    git(path, 'commit', '-qm', 'init');
  };
  const run = (args) => spawnSync(dots, ['clean', ...args], { env, encoding: 'utf8' });
  const calls = () => (existsSync(rec) ? readFileSync(rec, 'utf8') : '');
  return { home, git, file, age, repo, run, calls };
}

// A project with every kind of folder, each aged or not, so one run shows which ones go.
function lay(s) {
  const p = join(s.home, 'Codes/proj');
  s.repo(p, 'target/\nnode_modules/\n.claude/\n');
  s.file(join(p, 'vendor/lib.php'));
  s.git(p, 'add', 'vendor');
  s.git(p, 'commit', '-qm', 'vendor');
  s.file(join(p, 'target/debug/app'));
  s.file(join(p, 'node_modules/a/index.js'));
  s.file(join(p, 'build/out.o'));
  s.age(join(p, 'target'));
  s.age(join(p, 'vendor'));
  s.age(join(p, 'build'));

  const pin = join(s.home, '.local/src/tool');
  s.repo(pin, '');
  s.file(join(pin, 'build/tool'));
  s.file(join(pin, 'vendor/dep.c'));
  s.git(pin, 'add', 'vendor');
  s.git(pin, 'commit', '-qm', 'vendor');
  s.age(join(pin, 'build'));
  s.age(join(pin, 'vendor'));

  for (const w of ['stale', 'dirty', 'fresh']) s.git(p, 'worktree', 'add', '-q', `.claude/worktrees/${w}`);
  s.file(join(p, '.claude/worktrees/stale/target/debug/app'));
  s.file(join(p, '.claude/worktrees/dirty/notes.txt'));
  s.age(join(p, '.claude/worktrees/stale'));
  s.age(join(p, '.claude/worktrees/dirty'));

  for (const c of ['old-task', 'ms-playwright']) {
    s.file(join(s.home, '.cache', c, 'f'));
    s.age(join(s.home, '.cache', c));
  }
  s.file(join(s.home, '.cache/live/f'));
  return p;
}

test('the dry run lists what has gone unused and touches nothing', (t) => {
  const s = scratch(t);
  const p = lay(s);
  const r = s.run([]);
  assert.equal(r.status, 0, r.stderr);
  for (const n of ['Codes/proj/target', 'Codes/proj/.claude/worktrees/stale', '.local/src/tool/build', '.cache/old-task']) {
    assert.ok(existsSync(join(s.home, n)), n);
  }
  assert.match(r.stdout, /and 4 smaller/);
  assert.match(r.stdout, /kept ~\/Codes\/proj\/\.claude\/worktrees\/dirty: uncommitted work/);
  assert.match(r.stdout, /then: pnpm store prune · npm cache clean --force · uv cache prune · podman image prune -f/);
  assert.match(r.stdout, /dots clean --yes removes it/);
  assert.equal(s.calls(), '');
  assert.ok(existsSync(join(p, 'node_modules')));
});

test('--yes removes stale output, worktrees and caches, keeps the rest, then prunes the package caches', (t) => {
  const s = scratch(t);
  const p = lay(s);
  const r = s.run(['--yes']);
  assert.equal(r.status, 0, r.stderr);
  const gone = ['Codes/proj/target', 'Codes/proj/.claude/worktrees/stale', '.local/src/tool/build', '.cache/old-task'];
  const kept = [
    'Codes/proj/node_modules',
    'Codes/proj/vendor',
    '.local/src/tool/vendor',
    'Codes/proj/build',
    'Codes/proj/.claude/worktrees/dirty',
    'Codes/proj/.claude/worktrees/fresh',
    '.cache/ms-playwright',
    '.cache/live',
  ];
  for (const n of gone) assert.ok(!existsSync(join(s.home, n)), `${n} should be gone`);
  for (const n of kept) assert.ok(existsSync(join(s.home, n)), `${n} should be kept`);
  const listed = s.git(p, 'worktree', 'list').toString();
  assert.ok(!listed.includes('worktrees/stale'));
  assert.ok(listed.includes('worktrees/dirty'));
  assert.equal(s.calls(), 'pnpm store prune\nnpm cache clean --force\nuv cache prune\npodman image prune -f\n');
  assert.match(r.stdout, /free before, .* now/);
});

test('an unknown argument prints the usage', (t) => {
  const r = scratch(t).run(['--all']);
  assert.equal(r.status, 2);
  assert.match(r.stderr, /usage: dots clean \[--yes\]/);
});
