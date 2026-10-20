import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawn, spawnSync } from 'node:child_process';
import { closeSync, mkdirSync, mkdtempSync, openSync, readFileSync, readSync, readdirSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

// Every channel dots theme reloads points into the temp dir, so a name that slipped through still reaches nothing live.
const dots = new URL('../../bin/dots', import.meta.url).pathname;

function isolated(state) {
  const env = Object.assign({}, process.env, {
    XDG_STATE_HOME: state, WAYLAND_DISPLAY: '', DBUS_SESSION_BUS_ADDRESS: `unix:path=${state}/no-bus`,
    TMUX_TMPDIR: state, DCONF_PROFILE: `${state}/no-profile`, DOTS_CHROMIUM_POLICY_DIR: `${state}/no-policy`,
  });
  delete env.TMUX;
  return env;
}

test('a theme name that is not a plain lower-case word is refused and changes nothing', (t) => {
  const state = mkdtempSync(join(tmpdir(), 'dots-name-'));
  t.after(() => rmSync(state, { recursive: true, force: true }));
  for (const name of ['"x', '../paper', '-x', 'a b', 'Paper', '', 'ünï', 'a'.repeat(33)]) {
    const env = isolated(state);
    const r = spawnSync(dots, ['theme', name], { env, encoding: 'utf8' });
    assert.equal(r.status, 1, `${JSON.stringify(name)}: ${r.stderr}`);
    assert.match(r.stderr, /dots: (theme .*: not a theme name|usage: dots theme <name>)/);
  }
  assert.deepEqual(readdirSync(state), []);
});

// Two switches at once each wrote half the fragments, leaving a desktop drawn from both.
test('a switch waits while another holds the theme lock', async (t) => {
  const state = mkdtempSync(join(tmpdir(), 'dots-lock-'));
  t.after(() => rmSync(state, { recursive: true, force: true }));
  mkdirSync(join(state, 'dots'));
  const holder = spawn('flock', [join(state, 'dots/theme.lock'), '-c', 'echo held; sleep 1'], { stdio: ['ignore', 'pipe', 'ignore'] });
  await new Promise((r) => holder.stdout.once('data', r));
  const t0 = Date.now();
  const r = spawnSync(dots, ['theme', 'blueprint'], { env: isolated(state), encoding: 'utf8' });
  assert.equal(r.status, 0, r.stderr);
  assert.ok(Date.now() - t0 >= 800, `the switch ran after ${Date.now() - t0} ms, while the lock was held`);
  assert.equal(readFileSync(join(state, 'dots/theme'), 'utf8'), 'blueprint\n');
});

// niri, the shell and tmux read fragments while a switch writes them; truncating in place let a reader see half a file.
test('a switch replaces a changed fragment whole, so a reader of the old one still reads all of it', (t) => {
  const state = mkdtempSync(join(tmpdir(), 'dots-atomic-'));
  t.after(() => rmSync(state, { recursive: true, force: true }));
  assert.equal(spawnSync(dots, ['theme', 'paper'], { env: isolated(state) }).status, 0);
  const path = join(state, 'dots/theme-out/niri.kdl');
  const paper = readFileSync(path, 'utf8');
  const fd = openSync(path, 'r');
  assert.equal(spawnSync(dots, ['theme', 'blueprint'], { env: isolated(state) }).status, 0);
  const buf = Buffer.alloc(paper.length + 1);
  const n = readSync(fd, buf, 0, buf.length, 0);
  closeSync(fd);
  assert.equal(buf.subarray(0, n).toString(), paper);
  assert.notEqual(readFileSync(path, 'utf8'), paper);
  assert.deepEqual(readdirSync(join(state, 'dots/theme-out')).filter((f) => f.includes('.tmp')), []);
});
