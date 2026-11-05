// dots colorscheme against real headless mpv players, which open their sockets through dots-ipc.lua; slower than shell/lib's tests, so it runs with test-dots.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawn, spawnSync } from 'node:child_process';
import { cpSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { connect, createServer } from 'node:net';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const dots = new URL('../../bin/dots', import.meta.url).pathname;
const repo = new URL('../..', import.meta.url).pathname;

// bin/dots finds its repo from its own path, so a copy of it beside Artboard turned dark switches between the two.
function fixture(t) {
  const root = mkdtempSync(join(tmpdir(), 'dots-mpv-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  for (const d of ['bin/dots', 'shell/lib', 'shell/newtab', 'colorschemes']) cpSync(join(repo, d), join(root, d), { recursive: true });
  // A dark scheme under its own name; Artboard's light colours on a dark surface would fail the colorscheme check.
  writeFileSync(join(root, 'colorschemes/night.toml'), readFileSync(join(repo, 'colorschemes/github-dark.toml'), 'utf8').replace('name = "github-dark"', 'name = "night"'));
  const state = join(root, 'state');
  mkdirSync(state);
  return { dots: join(root, 'bin/dots'), state };
}

// Every channel dots colorscheme reloads points into the temp dir, so no live player, bus or terminal is reached.
function isolated(state) {
  const env = Object.assign({}, process.env, {
    XDG_STATE_HOME: state, WAYLAND_DISPLAY: '', DBUS_SESSION_BUS_ADDRESS: `unix:path=${state}/no-bus`,
    TMUX_TMPDIR: state, DCONF_PROFILE: `${state}/no-profile`, XDG_RUNTIME_DIR: state, DOTS_AGENT_HOME: `${state}/agents`,
  });
  delete env.TMUX;
  return env;
}

const ipcScript = new URL('../../home/dot_config/mpv/scripts/dots-ipc.lua', import.meta.url).pathname;
const hasMpv = spawnSync('sh', ['-c', 'command -v mpv']).stdout.length > 0;

function mpvAsk(sock, command) {
  return new Promise((resolve, reject) => {
    const c = connect(sock);
    let buf = '';
    c.on('data', (d) => {
      buf += d;
      if (buf.includes('\n')) {
        c.end();
        resolve(JSON.parse(buf.split('\n')[0]).data);
      }
    });
    c.on('error', reject);
    c.write(JSON.stringify({ command }) + '\n');
  });
}

async function until(f, ms) {
  const end = Date.now() + ms;
  while (!(await f())) {
    if (Date.now() > end) return false;
    await new Promise((r) => setTimeout(r, 50));
  }
  return true;
}

// The players run headless on this test's empty display, so no live mpv is reached; each opens its socket through the script mpv.conf loads from scripts/.
function player(state) {
  return spawn('mpv', ['--no-config', '--idle', '--no-video', '--no-terminal', `--script=${ipcScript}`], { env: isolated(state), stdio: 'ignore' });
}

test('a switch recolours every open mpv within a second, and each socket goes when its player quits', { skip: !hasMpv }, async (t) => {
  const { dots, state } = fixture(t);
  const players = [player(state), player(state)];
  t.after(() => players.forEach((p) => p.kill('SIGKILL')));
  const socks = players.map((p) => join(state, `mpv-${p.pid}.sock`));
  assert.ok(await until(() => socks.every((s) => existsSync(s)), 5000), 'both players opened their sockets');
  assert.equal(spawnSync(dots, ['colorscheme', 'night'], { env: isolated(state) }).status, 0);
  for (const s of socks) assert.equal((await mpvAsk(s, ['get_property', 'osd-color'])).toLowerCase(), '#fff0f6fc');
  const t0 = Date.now();
  assert.equal(spawnSync(dots, ['colorscheme', 'artboard'], { env: isolated(state) }).status, 0);
  for (const s of socks) {
    assert.ok(await until(async () => (await mpvAsk(s, ['get_property', 'osd-color'])).toLowerCase() === '#ff15171b', 1000), s);
    assert.equal((await mpvAsk(s, ['get_property', 'script-opts']))['osc-background_color'], '#ffffff');
  }
  assert.ok(Date.now() - t0 <= 1000, `${Date.now() - t0} ms`);
  assert.equal(readFileSync(join(state, 'dots/theme-out/notice'), 'utf8'), 'colorscheme artboard: gsettings did not reload\n');
  for (const s of socks) await mpvAsk(s, ['quit']).catch(() => {});
  assert.ok(await until(() => socks.every((s) => !existsSync(s)), 5000), 'both sockets are gone after quit');
  assert.equal(spawnSync(dots, ['colorscheme', 'night'], { env: isolated(state) }).status, 0);
});

// A crash runs no shutdown hook, so its socket stays; the next player and the next switch must not trip on it.
test('a socket left by a killed mpv is removed by the next switch, which still reaches the live player', { skip: !hasMpv }, async (t) => {
  const { dots, state } = fixture(t);
  const dead = player(state);
  t.after(() => dead.kill('SIGKILL'));
  const deadSock = join(state, `mpv-${dead.pid}.sock`);
  assert.ok(await until(() => existsSync(deadSock), 5000));
  const exited = new Promise((r) => dead.once('exit', r));
  dead.kill('SIGKILL');
  await exited;
  assert.ok(existsSync(deadSock), 'a killed mpv leaves its socket');
  const live = player(state);
  t.after(() => live.kill('SIGKILL'));
  const liveSock = join(state, `mpv-${live.pid}.sock`);
  assert.ok(await until(() => existsSync(liveSock), 5000));
  assert.equal(spawnSync(dots, ['colorscheme', 'night'], { env: isolated(state) }).status, 0);
  assert.equal(existsSync(deadSock), false);
  assert.equal((await mpvAsk(liveSock, ['get_property', 'osd-color'])).toLowerCase(), '#fff0f6fc');
  assert.equal(readFileSync(join(state, 'dots/theme-out/notice'), 'utf8'), 'colorscheme night: gsettings did not reload\n');
});


// A player started with its own --input-ipc-server keeps it; only a socket named by a dead pid is swept.
test('a switch leaves a socket not named by a pid, such as a player given its own', async (t) => {
  const state = mkdtempSync(join(tmpdir(), 'dots-mpv-'));
  t.after(() => rmSync(state, { recursive: true, force: true }));
  const own = join(state, 'mpv-music.sock');
  const server = createServer(() => {}).listen(own);
  t.after(() => server.close());
  await new Promise((r) => server.once('listening', r));
  assert.equal(spawnSync(dots, ['colorscheme', 'artboard'], { env: isolated(state) }).status, 0);
  assert.ok(existsSync(own), 'mpv-music.sock is still there');
});
