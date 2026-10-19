// dots update against a scratch clone, with sudo, dnf, rpm and chezmoi replaced by stubs that log to one file.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { chmodSync, copyFileSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { delimiter, join } from 'node:path';
import { spawnSync } from 'node:child_process';

const bin = new URL('../../bin/', import.meta.url).pathname;
const GIT = 'git -c user.name=t -c user.email=t@t';

const sh = (cwd, cmd) => {
  const r = spawnSync('sh', ['-c', cmd], { cwd, encoding: 'utf8' });
  assert.equal(r.status, 0, `${cmd}: ${r.stderr}`);
  return r.stdout.trim();
};

const BEFORE = 'bash.aarch64 5.2-1\ncurl.aarch64 8.0-1\nfish.aarch64 4.0-1\n';
const AFTER = 'bash.aarch64 5.2-2\ncurl.aarch64 8.0-2\nfish.aarch64 4.0-1\n';
const stub = (dir, name, body) => {
  writeFileSync(join(dir, name), `#!/bin/sh\n${body}\n`);
  chmodSync(join(dir, name), 0o755);
};

// opts.upgrade: dnf upgrade changes two packages; opts.chezmoi: what chezmoi apply prints.
function scratch(opts = {}) {
  const root = realpathSync(mkdtempSync(join(tmpdir(), 'dots-update-')));
  const stubs = join(root, 'stubs');
  mkdirSync(stubs);
  const log = join(root, 'order.log');
  const sudoLog = join(root, 'sudo.log');
  const state = join(root, 'upgraded');
  const repo = join(root, 'repo');
  writeFileSync(join(root, 'before'), BEFORE);
  writeFileSync(join(root, 'after'), AFTER);
  writeFileSync(join(root, 'chezmoi.out'), opts.chezmoi ?? '');

  sh(root, 'git init -q --bare -b main origin.git');
  sh(root, 'git clone -q origin.git seed 2>/dev/null');
  mkdirSync(join(root, 'seed/bin'));
  for (const f of ['dots', 'dots-update']) copyFileSync(join(bin, f), join(root, 'seed/bin', f));
  sh(join(root, 'seed'), `chmod +x bin/*; git add bin; ${GIT} commit -qm seed; git push -q origin HEAD:main`);
  sh(root, 'git clone -q origin.git repo');

  stub(stubs, 'sudo', `echo "$*" >> ${sudoLog}\nif [ "$1" = -v ] || [ "$1 $2" = "-n -v" ]; then exit 0; fi\nshift\nexec "$@"`);
  stub(
    stubs,
    'dnf',
    `echo "dnf $* pulled=$(test -f ${repo}/upstream.txt && echo yes || echo no)" >> ${log}\n${opts.upgrade ? `if [ "$1" = upgrade ]; then touch ${state}; fi` : ''}`,
  );
  stub(stubs, 'rpm', `if [ -e ${state} ]; then cat ${join(root, 'after')}; else cat ${join(root, 'before')}; fi`);
  stub(stubs, 'chezmoi', `echo "chezmoi $*" >> ${log}\ncat ${join(root, 'chezmoi.out')}`);

  return { root, repo, log, sudoLog, stubs };
}

// A second clone pushes a commit upstream, which the scratch repo can fast-forward to.
const push = (s, name) => {
  const other = join(s.root, 'other');
  sh(s.root, 'test -d other || git clone -q origin.git other');
  sh(other, `echo ${name} > ${name}.txt; git add ${name}.txt; ${GIT} commit -qm ${name}; git push -q origin HEAD:main`);
};

const run = (s) =>
  spawnSync(join(s.repo, 'bin/dots'), ['update'], {
    encoding: 'utf8',
    env: { PATH: s.stubs + delimiter + process.env.PATH, HOME: s.root },
  });

const lines = (path) => readFileSync(path, 'utf8').trim().split('\n');

test('update pulls, upgrades, applies, and ends with one summary line', () => {
  const s = scratch({ upgrade: true, chezmoi: 'dots: pin yazi 26.10.0\nsome other chezmoi output\n' });
  push(s, 'upstream');
  const r = run(s);
  assert.equal(r.status, 0, r.stderr);
  const out = r.stdout.trim().split('\n');
  assert.equal(out.at(-1), 'dnf: 2 upgraded · pins: 1 changed');
  assert.ok(out.includes('some other chezmoi output'), 'chezmoi output reaches the terminal');
  assert.deepEqual(lines(s.log), ['dnf upgrade -y pulled=yes', 'chezmoi apply']);
});

test('only the first sudo call can prompt', () => {
  const s = scratch({ upgrade: true });
  assert.equal(run(s).status, 0);
  const calls = lines(s.sudoLog);
  assert.equal(calls[0], '-v');
  assert.ok(calls.includes('-n dnf upgrade -y'));
  for (const c of calls.slice(1)) assert.ok(c.startsWith('-n '), c);
});

test('nothing to upgrade and no pin lines is zero and zero', () => {
  const s = scratch({ chezmoi: 'unrelated\n' });
  const r = run(s);
  assert.equal(r.status, 0, r.stderr);
  assert.equal(r.stdout.trim().split('\n').at(-1), 'dnf: 0 upgraded · pins: 0 changed');
});

test('a diverged clone stops before dnf with no summary', () => {
  const s = scratch({ upgrade: true });
  push(s, 'upstream');
  sh(s.repo, `echo mine > mine.txt; git add mine.txt; ${GIT} commit -qm mine`);
  const r = run(s);
  assert.notEqual(r.status, 0);
  assert.match(r.stderr, /dots: git pull failed/);
  assert.doesNotMatch(r.stdout, /upgraded/);
  assert.throws(() => readFileSync(s.log), /ENOENT/);
});
