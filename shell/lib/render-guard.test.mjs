import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, readdirSync, existsSync, rmSync, symlinkSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const cli = new URL('./colorscheme-render.mjs', import.meta.url).pathname;
const tree = (dir) => readdirSync(dir, { recursive: true }).sort();

// A scratch home whose quickshell link points at a stand-in for another checkout.
const home = (t) => {
  const root = mkdtempSync(join(tmpdir(), 'dots-guard-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const other = join(root, 'other-checkout');
  mkdirSync(other);
  mkdirSync(join(root, 'config'));
  symlinkSync(other, join(root, 'config/quickshell'));
  return root;
};

// Built from nothing, so no key of the real session can reach the render.
const render = (root, extra = {}) => spawnSync('node', [cli, 'artboard'], {
  encoding: 'utf8',
  env: {
    HOME: root,
    XDG_CONFIG_HOME: join(root, 'config'),
    XDG_DATA_HOME: join(root, 'data'),
    XDG_CACHE_HOME: join(root, 'cache'),
    PATH: process.env.PATH,
    WAYLAND_DISPLAY: '',
    DBUS_SESSION_BUS_ADDRESS: `unix:path=${join(root, 'no-bus')}`,
    DOTS_AGENT_HOME: join(root, 'agent'),
    ...extra,
  },
});

test('a render from a checkout the live shell does not run from writes nothing', (t) => {
  const root = home(t);
  const before = tree(root);
  const r = render(root);
  assert.equal(r.status, 1);
  assert.match(r.stderr, /set XDG_STATE_HOME to render elsewhere/);
  assert.deepEqual(tree(root), before);
});

test('an explicit state folder renders even when the live shell runs elsewhere', (t) => {
  const root = home(t);
  const state = join(root, 'state');
  const r = render(root, { XDG_STATE_HOME: state });
  assert.equal(r.status, 0, r.stderr);
  assert.ok(existsSync(join(state, 'dots/theme-out/niri.kdl')));
});
