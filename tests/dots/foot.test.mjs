// dots-foot with stub footclient and foot first on PATH, each writing the arguments it got.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { chmodSync, existsSync, mkdirSync, mkdtempSync, readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { delimiter, join } from 'node:path';

const bin = new URL('../../bin/', import.meta.url).pathname;

function run(clientExit, args = [], extraEnv = {}) {
  const dir = mkdtempSync(join(tmpdir(), 'dots-foot-'));
  const stubs = join(dir, 'stubs');
  mkdirSync(stubs);
  for (const [name, exit] of [['footclient', clientExit], ['foot', 0]]) {
    writeFileSync(join(stubs, name), `#!/bin/sh\nprintf '%s\\n' "$@" > "${dir}/${name}.args"\nexit ${exit}\n`);
    chmodSync(join(stubs, name), 0o755);
  }
  mkdirSync(join(dir, 'dots/theme-out'), { recursive: true });
  writeFileSync(join(dir, 'dots/theme-out/foot.args'), 'main.initial-color-theme=dark\ncolors-dark.cursor=0A1526 7FE3F0\n');
  const r = spawnSync(join(bin, 'dots-foot'), args, { env: { ...process.env, PATH: stubs + delimiter + process.env.PATH, XDG_STATE_HOME: dir, DOTS_DEV_DIR: '', ...extraEnv }, encoding: 'utf8' });
  const got = (name) => (existsSync(join(dir, `${name}.args`)) ? readFileSync(join(dir, `${name}.args`), 'utf8').trim().split('\n') : null);
  return { status: r.status, footclient: got('footclient'), foot: got('foot') };
}

test('a new window asks the foot server for the current theme', () => {
  const r = run(0, ['-e', 'kak']);
  assert.equal(r.status, 0);
  assert.deepEqual(r.footclient, ['-N', '-o', 'main.initial-color-theme=dark', '-o', 'colors-dark.cursor=0A1526 7FE3F0', '-e', 'kak']);
  assert.equal(r.foot, null);
});

test('without a server, plain foot opens the window', () => {
  const r = run(1, ['-e', 'kak']);
  assert.equal(r.status, 0);
  assert.deepEqual(r.foot, ['-e', 'kak']);
});

test('a nested just dev session never asks the live foot server', () => {
  const r = run(0, ['-e', 'kak'], { DOTS_DEV_DIR: '/tmp/dots-dev-x' });
  assert.equal(r.footclient, null);
  assert.deepEqual(r.foot, ['-e', 'kak']);
});
