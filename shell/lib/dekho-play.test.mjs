import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { chmodSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const bin = new URL('../../bin/dots-dekho-play', import.meta.url).pathname;

// The unit gets the user manager's environment, so dekho's hosts, key, dirs and the caller's display reach it only through systemd-run's --setenv; a fake systemd-run logs the command it is given.
test('the play unit is given every DEKHO_* and the key, dirs and display the caller has set, by name', (t) => {
  const dir = mkdtempSync(join(tmpdir(), 'dekho-play-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const log = join(dir, 'argv');
  writeFileSync(join(dir, 'systemd-run'), `#!/bin/sh\nprintf '%s\\n' "$@" > "${log}"\n`);
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
