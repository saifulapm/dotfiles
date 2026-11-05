// The chezmoi theme script renders the saved colorscheme, and bin/dots-dev can seed the nested session with one.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { cpSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const repo = new URL('../../', import.meta.url).pathname;
const read = (f) => readFileSync(join(repo, f), 'utf8');

test('the theme script hashes the colorschemes and renders the saved one', () => {
  const script = read('home/.chezmoiscripts/run_onchange_after_10-theme.sh.tmpl');
  assert.match(script, /^# theme sources hash:.*"colorschemes\/\*"/m);
  for (const f of ['colorscheme\\*\\.mjs', 'render-out\\.mjs', 'theme\\.mjs', 'apps\\.mjs', 'toml\\.mjs']) assert.match(script, new RegExp(`shell/lib/${f}`), f);
  assert.match(script, /^node .*colorscheme-render\.mjs" \| quote \}\} --saved \|\| die/m);
  assert.doesNotMatch(script, /paper|theme-render\.mjs/);
});

test('dots-dev renders DOTS_DEV_SCHEME with the colorscheme render, artboard by default, and no legacy theme', () => {
  const dev = read('bin/dots-dev');
  assert.match(dev, /^: "\$\{DOTS_DEV_SCHEME:=artboard\}"$/m);
  assert.match(dev, /colorscheme-render\.mjs" "\$DOTS_DEV_SCHEME"/);
  assert.doesNotMatch(dev, /theme-render\.mjs|DOTS_DEV_THEME/);
});

// A dark old theme saved on a machine became artboard on the next apply while GTK kept prefer-dark, since only a switch tells GTK (m79 review).
test('the script, run where a dark old theme is saved, saves artboard and tells GTK light', (t) => {
  const root = realpathSync(mkdtempSync(join(tmpdir(), 'theme-script-')));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  for (const d of ['bin/dots', 'shell/lib', 'shell/newtab', 'colorschemes', 'home/.chezmoitemplates/lib.sh']) cpSync(join(repo, d), join(root, d), { recursive: true });
  writeFileSync(join(root, '.chezmoiroot'), 'home\n');
  const r = spawnSync('chezmoi', ['--config', join(root, 'none.toml'), '--source', root, 'execute-template'], {
    input: read('home/.chezmoiscripts/run_onchange_after_10-theme.sh.tmpl'), encoding: 'utf8', env: { PATH: process.env.PATH, HOME: root },
  });
  assert.equal(r.status, 0, r.stderr);
  const state = join(root, 'state');
  mkdirSync(join(state, 'dots'), { recursive: true });
  writeFileSync(join(state, 'dots/theme'), 'hi-fi\n');
  const bin = join(root, 'stubs');
  mkdirSync(bin);
  writeFileSync(join(bin, 'gsettings'), `#!/bin/bash\necho "$*" >>${join(root, 'gsettings.log')}\n`, { mode: 0o755 });
  const env = {
    PATH: `${bin}:${process.env.PATH}`, HOME: root, XDG_STATE_HOME: state, WAYLAND_DISPLAY: '', DBUS_SESSION_BUS_ADDRESS: `unix:path=${root}/no-bus`,
    TMUX_TMPDIR: root, XDG_RUNTIME_DIR: root, DOTS_AGENT_HOME: join(root, 'agents'),
  };
  const run = spawnSync('bash', ['-c', r.stdout], { env, encoding: 'utf8' });
  assert.equal(run.status, 0, run.stderr);
  assert.equal(readFileSync(join(state, 'dots/theme'), 'utf8'), 'artboard\n');
  assert.match(readFileSync(join(root, 'gsettings.log'), 'utf8'), /color-scheme prefer-light/);
});
