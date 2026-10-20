import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawn, spawnSync } from 'node:child_process';
import { closeSync, existsSync, mkdirSync, mkdtempSync, openSync, readFileSync, readSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

// Every channel dots theme reloads points into the temp dir, so a name that slipped through still reaches nothing live.
const dots = new URL('../../bin/dots', import.meta.url).pathname;

function isolated(state) {
  const env = Object.assign({}, process.env, {
    XDG_STATE_HOME: state, WAYLAND_DISPLAY: '', DBUS_SESSION_BUS_ADDRESS: `unix:path=${state}/no-bus`,
    TMUX_TMPDIR: state, DCONF_PROFILE: `${state}/no-profile`, DOTS_CHROMIUM_POLICY_DIR: `${state}/no-policy`,
    DOTS_AGENT_HOME: `${state}/agents`,
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

// Each reload ran in the background with its status dropped, so an app left on the old theme said nothing.
test('a switch names the apps that did not reload in the notice the island shows', (t) => {
  const state = mkdtempSync(join(tmpdir(), 'dots-notice-'));
  t.after(() => rmSync(state, { recursive: true, force: true }));
  const notice = () => readFileSync(join(state, 'dots/theme-out/notice'), 'utf8');
  // No session bus refuses gsettings, and no policy dir refuses chromium.
  assert.equal(spawnSync(dots, ['theme', 'blueprint'], { env: isolated(state) }).status, 0);
  assert.equal(notice(), 'theme blueprint: chromium, gsettings did not reload\n');
  mkdirSync(join(state, 'no-policy'));
  assert.equal(spawnSync(dots, ['theme', 'paper'], { env: isolated(state) }).status, 0);
  assert.equal(notice(), 'theme paper: gsettings did not reload\n');
  assert.match(readFileSync(join(state, 'no-policy/color.json'), 'utf8'), /BrowserThemeColor/);
});

// The agents' configs name the theme qshell, and each reloads its file when it changes.
test('a switch writes the agent TUI themes into the apps that are installed, and no others', (t) => {
  const state = mkdtempSync(join(tmpdir(), 'dots-agents-'));
  t.after(() => rmSync(state, { recursive: true, force: true }));
  const home = join(state, 'agents');
  for (const d of ['.claude', '.config/opencode', '.config/amx']) mkdirSync(join(home, d), { recursive: true });
  assert.equal(spawnSync(dots, ['theme', 'artboard'], { env: isolated(state) }).status, 0);
  const out = (f) => readFileSync(join(state, 'dots/theme-out', f), 'utf8');
  assert.equal(readFileSync(join(home, '.claude/themes/dots.json'), 'utf8'), out('claude.json'));
  assert.equal(readFileSync(join(home, '.config/opencode/themes/qshell.json'), 'utf8'), out('opencode.json'));
  assert.equal(readFileSync(join(home, '.config/amx/themes/qshell.toml'), 'utf8'), out('amx.toml'));
  assert.equal(JSON.parse(out('claude.json')).base, 'light');
  assert.deepEqual(readdirSync(home, { recursive: true }).filter((f) => f.startsWith('.pi')), []);
  assert.equal(spawnSync(dots, ['theme', 'blueprint'], { env: isolated(state) }).status, 0);
  assert.equal(JSON.parse(readFileSync(join(home, '.claude/themes/dots.json'), 'utf8')).base, 'dark');
  mkdirSync(join(home, '.pi/agent'), { recursive: true });
  assert.equal(spawnSync(dots, ['theme', 'paper'], { env: isolated(state) }).status, 0);
  assert.equal(readFileSync(join(home, '.pi/agent/themes/dots.json'), 'utf8'), out('pi.json'));
});

// helix rereads its config, and with it the theme file, on USR1; this hx only answers on an empty WAYLAND_DISPLAY, so no real editor is reached.
test('a switch sends USR1 to helix on this display, so it rereads its theme', async (t) => {
  const state = mkdtempSync(join(tmpdir(), 'dots-helix-'));
  t.after(() => rmSync(state, { recursive: true, force: true }));
  const bin = join(state, 'bin');
  mkdirSync(bin);
  const got = join(state, 'usr1');
  writeFileSync(join(bin, 'hx'), `#!/bin/bash\ntrap 'echo got >${got}; exit 0' USR1\nwhile :; do sleep 0.05; done\n`, { mode: 0o755 });
  const hx = spawn(join(bin, 'hx'), [], { env: isolated(state), stdio: 'ignore' });
  t.after(() => hx.kill('SIGKILL'));
  await new Promise((r) => setTimeout(r, 200));
  assert.equal(spawnSync(dots, ['theme', 'paper'], { env: isolated(state) }).status, 0);
  for (let i = 0; i < 40 && !existsSync(got); i++) await new Promise((r) => setTimeout(r, 50));
  assert.equal(readFileSync(got, 'utf8'), 'got\n');
});
