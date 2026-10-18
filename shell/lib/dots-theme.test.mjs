import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, readdirSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

// Every channel dots theme reloads points into the temp dir, so a name that slipped through still reaches nothing live.
const dots = new URL('../../bin/dots', import.meta.url).pathname;

test('a theme name that is not a plain lower-case word is refused and changes nothing', (t) => {
  const state = mkdtempSync(join(tmpdir(), 'dots-name-'));
  t.after(() => rmSync(state, { recursive: true, force: true }));
  for (const name of ['"x', '../paper', '-x', 'a b', 'Paper', '', 'ünï', 'a'.repeat(33)]) {
    const env = Object.assign({}, process.env, {
      XDG_STATE_HOME: state, WAYLAND_DISPLAY: '', DBUS_SESSION_BUS_ADDRESS: `unix:path=${state}/no-bus`,
      TMUX_TMPDIR: state, DCONF_PROFILE: `${state}/no-profile`, DOTS_CHROMIUM_POLICY_DIR: `${state}/no-policy`,
    });
    delete env.TMUX;
    const r = spawnSync(dots, ['theme', name], { env, encoding: 'utf8' });
    assert.equal(r.status, 1, `${JSON.stringify(name)}: ${r.stderr}`);
    assert.match(r.stderr, /dots: (theme .*: not a theme name|usage: dots theme <name>)/);
  }
  assert.deepEqual(readdirSync(state), []);
});
