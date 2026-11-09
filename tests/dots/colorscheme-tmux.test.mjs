// dots colorscheme brings the open tmux along: its theme, and the colours amx gave each agent pane as its window-style, which a switch would leave on the old scheme.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const dots = new URL('../../bin/dots', import.meta.url).pathname;

// Every channel dots colorscheme reloads points into the temp dir, so no live tmux, player, bus or terminal is reached.
function isolated(state) {
  const env = Object.assign({}, process.env, {
    XDG_STATE_HOME: state, WAYLAND_DISPLAY: '', DBUS_SESSION_BUS_ADDRESS: `unix:path=${state}/no-bus`,
    TMUX_TMPDIR: state, DCONF_PROFILE: `${state}/no-profile`, XDG_RUNTIME_DIR: state, DOTS_AGENT_HOME: `${state}/agents`,
    AMX_STATE_DIR: `${state}/amx`,
  });
  delete env.TMUX;
  return env;
}

test("a switch sets every agent pane's window-style and amx's remembered colours to the terminal's new ink and paper, and leaves a plain window's alone", (t) => {
  const state = mkdtempSync(join(tmpdir(), 'dots-tmux-'));
  const env = isolated(state);
  const tmux = (...args) => spawnSync('tmux', args, { env, encoding: 'utf8' });
  t.after(() => {
    tmux('kill-server');
    rmSync(state, { recursive: true, force: true });
  });
  mkdirSync(join(state, 'amx'));
  writeFileSync(join(state, 'amx/background'), 'fg=#000000,bg=#ffffff\n');
  assert.equal(tmux('new-session', '-d', '-s', 'amx-agent', 'sleep 60').status, 0);
  assert.equal(tmux('new-session', '-d', '-s', 'plain', 'sleep 60').status, 0);
  // amx sets the colours its view last read on each agent session it spawns.
  assert.equal(tmux('set-option', '-t', 'amx-agent', 'window-style', 'fg=#000000,bg=#ffffff').status, 0);

  assert.equal(spawnSync(dots, ['colorscheme', 'gruvbox-material-dark'], { env }).status, 0);

  const foot = readFileSync(join(state, 'dots/theme-out/foot.ini'), 'utf8');
  const [ink, paper] = ['foreground', 'background'].map((k) => foot.match(new RegExp(`^${k}=([0-9A-F]{6})$`, 'm'))[1].toLowerCase());
  const style = `fg=#${ink},bg=#${paper}`;
  assert.equal(tmux('show-options', '-wv', '-t', 'amx-agent', 'window-style').stdout.trim(), style);
  assert.equal(tmux('show-options', '-wv', '-t', 'plain', 'window-style').stdout.trim(), '', 'a window amx never styled keeps none');
  assert.equal(readFileSync(join(state, 'amx/background'), 'utf8'), `${style}\n`);
  assert.equal(tmux('show-options', '-gv', 'status-style').stdout.trim(), readFileSync(join(state, 'dots/theme-out/tmux.conf'), 'utf8').match(/^set -g status-style "(.*)"$/m)[1]);
});

test("dots tmux-style puts the scheme's ink and paper back on an agent pane another terminal's colours reached, and in amx's memory", (t) => {
  const state = mkdtempSync(join(tmpdir(), 'dots-tmux-'));
  const env = isolated(state);
  const tmux = (...args) => spawnSync('tmux', args, { env, encoding: 'utf8' });
  t.after(() => {
    tmux('kill-server');
    rmSync(state, { recursive: true, force: true });
  });
  mkdirSync(join(state, 'amx'));
  assert.equal(spawnSync(dots, ['colorscheme', 'gruvbox-material-dark'], { env }).status, 0);
  // An amx view on the phone's terminal remembered its colours, and an agent spawned then took them.
  writeFileSync(join(state, 'amx/background'), 'fg=#111111,bg=#eeeeee\n');
  assert.equal(tmux('new-session', '-d', '-s', 'amx-phone', 'sleep 60').status, 0);
  assert.equal(tmux('set-option', '-t', 'amx-phone', 'window-style', 'fg=#111111,bg=#eeeeee').status, 0);

  assert.equal(spawnSync(dots, ['tmux-style'], { env }).status, 0);

  const foot = readFileSync(join(state, 'dots/theme-out/foot.ini'), 'utf8');
  const [ink, paper] = ['foreground', 'background'].map((k) => foot.match(new RegExp(`^${k}=([0-9A-F]{6})$`, 'm'))[1].toLowerCase());
  assert.equal(tmux('show-options', '-wv', '-t', 'amx-phone', 'window-style').stdout.trim(), `fg=#${ink},bg=#${paper}`);
  assert.equal(readFileSync(join(state, 'amx/background'), 'utf8'), `fg=#${ink},bg=#${paper}\n`);
});
