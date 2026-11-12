import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawn, spawnSync } from 'node:child_process';
import { mkdirSync, mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

// This test times a switch from the moment it sees the lock taken, so it runs in a file of its own, where no other test's switches hold up this one's event loop.
const dots = new URL('../../bin/dots', import.meta.url).pathname;

function isolated(state) {
  const env = Object.assign({}, process.env, {
    XDG_STATE_HOME: state, WAYLAND_DISPLAY: '', DBUS_SESSION_BUS_ADDRESS: `unix:path=${state}/no-bus`,
    TMUX_TMPDIR: state, DCONF_PROFILE: `${state}/no-profile`, XDG_RUNTIME_DIR: state,
    DOTS_AGENT_HOME: `${state}/agents`,
  });
  delete env.TMUX;
  return env;
}

// Two switches at once each wrote half the fragments, leaving a desktop drawn from both.
test('a switch waits while another holds the theme lock', async (t) => {
  const state = mkdtempSync(join(tmpdir(), 'dots-lock-'));
  t.after(() => rmSync(state, { recursive: true, force: true }));
  mkdirSync(join(state, 'dots'));
  const holder = spawn('flock', [join(state, 'dots/theme.lock'), '-c', 'echo held; sleep 1'], { stdio: ['ignore', 'pipe', 'ignore'] });
  await new Promise((r) => holder.stdout.once('data', r));
  const t0 = Date.now();
  const r = spawnSync(dots, ['colorscheme', 'artboard'], { env: isolated(state), encoding: 'utf8' });
  assert.equal(r.status, 0, r.stderr);
  assert.ok(Date.now() - t0 >= 800, `the switch ran after ${Date.now() - t0} ms, while the lock was held`);
  assert.equal(readFileSync(join(state, 'dots/theme'), 'utf8'), 'artboard\n');
});
