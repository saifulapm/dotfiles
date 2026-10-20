// dots update against a scratch clone, with sudo, dnf, rpm and chezmoi replaced by stubs that log to one file.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { chmodSync, copyFileSync, existsSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { delimiter, join } from 'node:path';
import { spawn, spawnSync } from 'node:child_process';

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

// opts.mise: fail to make mise up exit 1; the stub keeps the real mise out of every run. opts.claude: claude's version before and after claude update, or fail to make it fail; the stub keeps the real claude out of every run. opts.upgrade: dnf upgrade changes two packages; opts.chezmoi: what chezmoi apply prints; opts.hang: dnf upgrade never returns; opts.kernels: the modules dir's kernels, the booted one first; opts.niri: the pids pgrep reports for niri.
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

  stub(stubs, 'sudo', `echo "$*" >> ${sudoLog}\nif [ "$1" = -v ] || [ "$1 $2" = "-n -v" ] || [ "$1" = -k ]; then exit 0; fi\nshift\nexec "$@"`);
  stub(
    stubs,
    'dnf',
    `echo "dnf $* pulled=$(test -f ${repo}/upstream.txt && echo yes || echo no)" >> ${log}\n${opts.upgrade ? `if [ "$1" = upgrade ]; then touch ${state}; fi` : ''}${opts.hang ? `\necho $$ > ${join(root, 'dnf.pid')}\nexec sleep 60` : ''}`,
  );
  stub(stubs, 'rpm', `if [ -e ${state} ]; then cat ${join(root, 'after')}; else cat ${join(root, 'before')}; fi`);
  stub(stubs, 'chezmoi', `echo "chezmoi $*" >> ${log}\ncat ${join(root, 'chezmoi.out')}`);
  stub(stubs, 'mise', `echo "mise $*" >> ${log}\n${opts.mise === 'fail' ? 'exit 1' : 'exit 0'}`);
  const claude = Object.assign({ from: '2.1.303', to: '2.1.303', fail: false }, opts.claude);
  const version = join(root, 'claude.version');
  writeFileSync(version, claude.from);
  stub(stubs, 'claude', `case "$1" in\n--version) echo "$(cat ${version}) (Claude Code)" ;;\nupdate) echo "claude update" >> ${log}; ${claude.fail ? 'exit 1' : `echo ${claude.to} > ${version}`} ;;\nesac`);
  const kernels = opts.kernels ?? ['7.1.13-402.asahi.fc44.aarch64+16k'];
  const modules = join(root, 'modules');
  for (const k of kernels) mkdirSync(join(modules, k), { recursive: true });
  stub(stubs, 'uname', `case "$1" in -r) echo ${kernels[0]} ;; -m) echo aarch64 ;; *) exec /usr/bin/uname "$@" ;; esac`);
  stub(stubs, 'pgrep', `[ "$*" = "-x niri" ] && printf '%s\\n' ${(opts.niri ?? []).join(' ')}; exit 0`);

  return { root, repo, log, sudoLog, stubs, modules };
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
    env: { PATH: s.stubs + delimiter + process.env.PATH, HOME: s.root, DOTS_MODULES_DIR: s.modules },
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
  assert.deepEqual(lines(s.log), ['dnf upgrade -y pulled=yes', 'chezmoi apply', 'mise up', 'claude update']);
});

test('only the first sudo call can prompt', () => {
  const s = scratch({ upgrade: true });
  assert.equal(run(s).status, 0);
  const calls = lines(s.sudoLog);
  assert.equal(calls[0], '-v');
  assert.ok(calls.includes('-n dnf upgrade -y'));
  // sudo -k only drops the timestamp, so it never prompts; real sudo refuses -n with it.
  for (const c of calls.slice(1)) assert.ok(c.startsWith('-n ') || c === '-k', c);
});

test('an update ends by dropping the sudo timestamp', () => {
  const s = scratch({ upgrade: true });
  assert.equal(run(s).status, 0);
  assert.equal(lines(s.sudoLog).at(-1), '-k');
});

// A killed update runs no EXIT trap, and its keepalive went on renewing root's timestamp for good.
test('the sudo keepalive stops renewing once its update is killed', async () => {
  const s = scratch({ hang: true });
  const env = { PATH: s.stubs + delimiter + process.env.PATH, HOME: s.root, DOTS_SUDO_TICK: '0.2' };
  const p = spawn(join(s.repo, 'bin/dots'), ['update'], { env, stdio: 'ignore' });
  const renewals = () => lines(s.sudoLog).filter((c) => c === '-n -v').length;
  const wait = (ms) => new Promise((r) => setTimeout(r, ms));
  for (let i = 0; i < 50 && !(existsSync(s.log) && renewals() >= 2); i++) await wait(100);
  assert.ok(renewals() >= 2, 'the keepalive renews while the update runs');
  p.kill('SIGKILL');
  process.kill(Number(readFileSync(join(s.root, 'dnf.pid'), 'utf8')), 'SIGKILL');
  await wait(500);
  const after = renewals();
  await wait(1000);
  assert.equal(renewals(), after, 'no renewal after the update is gone');
});

// The summary said nothing of a new kernel or niri, which only a reboot puts in use.
test('a kernel newer than the booted one of its flavour adds reboot: needed', () => {
  const s = scratch({ kernels: ['7.1.13-401.asahi.fc44.aarch64+16k', '7.1.13-402.asahi.fc44.aarch64+16k', '7.1.6-400.asahi.fc44.aarch64+16k'] });
  const r = run(s);
  assert.equal(r.status, 0, r.stderr);
  assert.equal(r.stdout.trim().split('\n').at(-1), 'dnf: 0 upgraded · pins: 0 changed · reboot: needed');
});

test('a newer kernel of another flavour, or an older one, needs no reboot', () => {
  const s = scratch({ kernels: ['7.1.13-402.asahi.fc44.aarch64+16k', '7.1.14-400.asahi.fc44.aarch64', '7.1.6-400.asahi.fc44.aarch64+16k'] });
  assert.equal(run(s).stdout.trim().split('\n').at(-1), 'dnf: 0 upgraded · pins: 0 changed');
});

test('a niri whose binary the upgrade replaced adds reboot: needed', (t) => {
  const s = scratch();
  // A copy of sleep, removed while it runs, shows in /proc as niri does after dnf replaced it.
  copyFileSync('/usr/bin/sleep', join(s.root, 'niri'));
  chmodSync(join(s.root, 'niri'), 0o755);
  const p = spawn(join(s.root, 'niri'), ['30'], { stdio: 'ignore' });
  t.after(() => p.kill());
  rmSync(join(s.root, 'niri'));
  const r = spawnSync(join(s.repo, 'bin/dots'), ['update'], {
    encoding: 'utf8',
    env: { PATH: s.stubs + delimiter + process.env.PATH, HOME: s.root, DOTS_MODULES_DIR: s.modules },
  });
  assert.equal(r.status, 0, r.stderr);
  assert.equal(r.stdout.trim().split('\n').at(-1), 'dnf: 0 upgraded · pins: 0 changed', 'no niri reported yet');
  stub(s.stubs, 'pgrep', `[ "$*" = "-x niri" ] && echo ${p.pid}; exit 0`);
  assert.equal(run(s).stdout.trim().split('\n').at(-1), 'dnf: 0 upgraded · pins: 0 changed · reboot: needed');
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

// Claude Code's own updater is off in its settings, so dots update is what keeps it current.
test('update runs claude update after chezmoi apply and names the new version', () => {
  const s = scratch({ claude: { from: '2.1.303', to: '2.1.310' } });
  const r = run(s);
  assert.equal(r.status, 0, r.stderr);
  const order = lines(s.log).map((l) => l.split(' ').slice(0, 2).join(' '));
  assert.ok(order.indexOf('claude update') > order.indexOf('chezmoi apply'), order.join(', '));
  assert.equal(r.stdout.trim().split('\n').at(-1), 'dnf: 0 upgraded · pins: 0 changed · claude: 2.1.303 → 2.1.310');
});

test('a failed claude update is named in the summary, and the update still succeeds', () => {
  const r = run(scratch({ claude: { fail: true } }));
  assert.equal(r.status, 0, r.stderr);
  assert.equal(r.stdout.trim().split('\n').at(-1), 'dnf: 0 upgraded · pins: 0 changed · claude: update failed');
});

test('a failed mise up is named before the claude segment, and the update still succeeds', () => {
  const s = scratch({ mise: 'fail', claude: { from: '2.1.303', to: '2.1.310' } });
  const r = run(s);
  assert.equal(r.status, 0, r.stderr);
  assert.deepEqual(lines(s.log), ['dnf upgrade -y pulled=no', 'chezmoi apply', 'mise up', 'claude update']);
  assert.equal(r.stdout.trim().split('\n').at(-1), 'dnf: 0 upgraded · pins: 0 changed · mise: update failed · claude: 2.1.303 → 2.1.310');
});

test('a failed mise up alone ends the summary with mise: update failed', () => {
  const r = run(scratch({ mise: 'fail' }));
  assert.equal(r.status, 0, r.stderr);
  assert.equal(r.stdout.trim().split('\n').at(-1), 'dnf: 0 upgraded · pins: 0 changed · mise: update failed');
});

// Without these stubs a test run would execute the real mise up or claude update on this machine.
test('every run puts a stubs dir holding mise and claude first on PATH', () => {
  const s = scratch();
  assert.ok(existsSync(join(s.stubs, 'mise')), 'mise stub');
  assert.ok(existsSync(join(s.stubs, 'claude')), 'claude stub');
  assert.ok(run.toString().includes('PATH: s.stubs + delimiter'), 'run() puts the stubs first');
});
