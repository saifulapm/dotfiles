import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { chmodSync, existsSync, mkdtempSync, readFileSync, rmSync, utimesSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const bin = new URL('../../bin/dots-dekho-play', import.meta.url).pathname;

// The unit gets the user manager's environment, so dekho's hosts, key, dirs and the caller's display reach it only through systemd-run's --setenv; a fake systemd-run logs the command it is given.
test('the play unit is given every DEKHO_* and the key, dirs and display the caller has set, by name', (t) => {
  const dir = mkdtempSync(join(tmpdir(), 'dekho-play-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const log = join(dir, 'argv');
  // As the unit would, it writes dekho's first event into the session file it was handed.
  writeFileSync(join(dir, 'systemd-run'), `#!/bin/sh\nprintf '%s\\n' "$@" > "${log}"\nfor a; do case $a in StandardOutput=truncate:*) echo '{"event":"status"}' > "\${a#StandardOutput=truncate:}" ;; esac; done\n`);
  // Inactive, so the stop before the run returns at once.
  writeFileSync(join(dir, 'systemctl'), '#!/bin/sh\nexit 3\n');
  chmodSync(join(dir, 'systemd-run'), 0o755);
  chmodSync(join(dir, 'systemctl'), 0o755);
  const env = {
    PATH: `${dir}:${process.env.PATH}`, HOME: dir, XDG_RUNTIME_DIR: dir, DOTS_DEKHO_UNIT: 'dekho-play-unit-test', DOTS_DEKHO: '/opt/dekho',
    DEKHO_TMDB_URL: 'http://127.0.0.1:9', DEKHO_NO_DHT: '1', TMDB_API_KEY: 'fake-key',
    XDG_CONFIG_HOME: `${dir}/config`, XDG_CACHE_HOME: `${dir}/cache`, XDG_STATE_HOME: `${dir}/state`,
    WAYLAND_DISPLAY: 'wayland-7', OTHER_VAR: 'not passed',
  };
  const r = spawnSync('bash', [bin, '--session', `${dir}/s.ndjson`, '--id', '900002', '--kind', 'tv'], { env, encoding: 'utf8', timeout: 3000 });
  assert.equal(r.status, 0, r.stderr);
  const argv = readFileSync(log, 'utf8').trimEnd().split('\n');
  assert.deepEqual(argv.filter((a) => a.startsWith('--setenv')).sort(), [
    '--setenv=DEKHO_NO_DHT', '--setenv=DEKHO_TMDB_URL', '--setenv=TMDB_API_KEY', '--setenv=WAYLAND_DISPLAY',
    '--setenv=XDG_CACHE_HOME', '--setenv=XDG_CONFIG_HOME', '--setenv=XDG_STATE_HOME',
  ]);
  assert.deepEqual(argv.slice(argv.indexOf('--')), ['--', '/opt/dekho', 'play', '--json', '--id', '900002', '--kind', 'tv']);
});

// A fake systemd-run and an always-inactive systemctl in a scratch dir; returns the dir and a runner.
function rig(t, systemdRun) {
  const dir = mkdtempSync(join(tmpdir(), 'dekho-play-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  writeFileSync(join(dir, 'systemd-run'), `#!/bin/sh\n${systemdRun}\n`);
  writeFileSync(join(dir, 'systemctl'), '#!/bin/sh\nexit 3\n');
  chmodSync(join(dir, 'systemd-run'), 0o755);
  chmodSync(join(dir, 'systemctl'), 0o755);
  const env = { PATH: `${dir}:${process.env.PATH}`, HOME: dir, XDG_RUNTIME_DIR: dir, DOTS_DEKHO_UNIT: 'dekho-play-unit-test' };
  const play = (session) => spawnSync('bash', [bin, '--session', session, '--id', '1', '--kind', 'movie'], { env, encoding: 'utf8', timeout: 5000 });
  return { dir, play };
}

const events = (file) => readFileSync(file, 'utf8').trimEnd().split('\n').map((l) => JSON.parse(l));

// Starting draws an error and its exit; a play that never starts writes no event of its own, so the script writes them.
test('a unit systemd-run refuses leaves an error and exit 1 in the session file', (t) => {
  const { dir, play } = rig(t, 'exit 1');
  const r = play(`${dir}/s.ndjson`);
  assert.equal(r.status, 1);
  const got = events(`${dir}/s.ndjson`);
  assert.equal(got[0].event, 'error');
  assert.match(got[0].text, /dekho did not start/);
  assert.deepEqual(got[1], { event: 'exit', code: 1 });
});

test('a unit that ends at once without an event, as one whose dekho is missing does, leaves an error and exit 1', (t) => {
  const { dir, play } = rig(t, 'exit 0');
  const r = play(`${dir}/s.ndjson`);
  assert.equal(r.status, 1);
  assert.deepEqual(events(`${dir}/s.ndjson`).map((e) => e.event), ['error', 'exit']);
});

test('session files over a day old are swept, a newer one is kept', (t) => {
  const { dir, play } = rig(t, 'for a; do case $a in StandardOutput=truncate:*) echo \'{"event":"status"}\' > "${a#StandardOutput=truncate:}" ;; esac; done');
  const runtime = join(dir, 'dekho');
  spawnSync('mkdir', ['-p', runtime]);
  const old = join(runtime, 'session-1.ndjson');
  const recent = join(runtime, 'session-2.ndjson');
  writeFileSync(old, '{}\n');
  writeFileSync(recent, '{}\n');
  const twoDays = Date.now() / 1000 - 2 * 86400;
  utimesSync(old, twoDays, twoDays);
  const r = play(join(runtime, 'session-3.ndjson'));
  assert.equal(r.status, 0, r.stderr);
  assert.equal(existsSync(old), false);
  assert.equal(existsSync(recent), true);
});

// A trailer runs `dekho trailer` under a unit of its own, so its stop before each run, --stop and --status never touch the film's; a systemctl stub logs what it was asked.
function trailerRig(t) {
  const dir = mkdtempSync(join(tmpdir(), 'dekho-play-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const runLog = join(dir, 'run-argv');
  const ctlLog = join(dir, 'ctl-argv');
  writeFileSync(join(dir, 'systemd-run'), `#!/bin/sh\nprintf '%s\\n' "$@" > "${runLog}"\nfor a; do case $a in StandardOutput=truncate:*) echo '{"event":"status"}' > "\${a#StandardOutput=truncate:}" ;; esac; done\n`);
  writeFileSync(join(dir, 'systemctl'), `#!/bin/sh\necho "$*" >> "${ctlLog}"\nexit 3\n`);
  chmodSync(join(dir, 'systemd-run'), 0o755);
  chmodSync(join(dir, 'systemctl'), 0o755);
  const env = { PATH: `${dir}:${process.env.PATH}`, HOME: dir, XDG_RUNTIME_DIR: dir, DOTS_DEKHO_UNIT: 'dekho-play-unit-test', DOTS_DEKHO: '/opt/dekho' };
  const run = (...args) => spawnSync('bash', [bin, ...args], { env, encoding: 'utf8', timeout: 5000 });
  const lines = (f) => (existsSync(f) ? readFileSync(f, 'utf8').trimEnd().split('\n') : []);
  return { dir, run, runArgv: () => lines(runLog), ctl: () => lines(ctlLog) };
}

test("--trailer runs dekho trailer under the film's unit name with -trailer, and its stop first touches only that unit", (t) => {
  const { dir, run, runArgv, ctl } = trailerRig(t);
  const r = run('--trailer', '--session', `${dir}/t.ndjson`, '--id', '401', '--kind', 'movie');
  assert.equal(r.status, 0, r.stderr);
  const argv = runArgv();
  assert.equal(argv[argv.indexOf('--unit') + 1], 'dekho-play-unit-test-trailer');
  assert.deepEqual(argv.slice(argv.indexOf('--')), ['--', '/opt/dekho', 'trailer', '--json', '--id', '401', '--kind', 'movie']);
  assert.ok(ctl().length > 0);
  assert.ok(ctl().every((l) => l.includes('dekho-play-unit-test-trailer.service')), ctl().join('\n'));
  assert.equal(readFileSync(join(dir, 'dekho', 'dekho-play-unit-test-trailer.session'), 'utf8').trim(), `${dir}/t.ndjson`);
});

test('a film run still runs dekho play under its own unit', (t) => {
  const { dir, run, runArgv, ctl } = trailerRig(t);
  assert.equal(run('--session', `${dir}/s.ndjson`, '--id', '1', '--kind', 'movie').status, 0);
  const argv = runArgv();
  assert.equal(argv[argv.indexOf('--unit') + 1], 'dekho-play-unit-test');
  assert.deepEqual(argv.slice(argv.indexOf('--') + 1, argv.indexOf('--') + 4), ['/opt/dekho', 'play', '--json']);
  assert.ok(ctl().every((l) => l.includes('dekho-play-unit-test.service')), ctl().join('\n'));
});

test('--trailer --stop and --trailer --status act on the trailer unit alone', (t) => {
  const { run, ctl } = trailerRig(t);
  assert.equal(run('--trailer', '--stop').status, 0);
  assert.deepEqual(JSON.parse(run('--trailer', '--status').stdout), { active: false, session: '' });
  assert.ok(ctl().length > 0);
  assert.ok(ctl().every((l) => l.includes('dekho-play-unit-test-trailer.service')), ctl().join('\n'));
});
