// dots theme against real headless mpv players, which open their sockets through dots-ipc.lua; slower than shell/lib's tests, so it runs with test-dots.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawn, spawnSync } from 'node:child_process';
import { existsSync, mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { connect, createServer } from 'node:net';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const dots = new URL('../../bin/dots', import.meta.url).pathname;

// Every channel dots theme reloads points into the temp dir, so no live player, bus or terminal is reached.
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
  const state = mkdtempSync(join(tmpdir(), 'dots-mpv-'));
  t.after(() => rmSync(state, { recursive: true, force: true }));
  const players = [player(state), player(state)];
  t.after(() => players.forEach((p) => p.kill('SIGKILL')));
  const socks = players.map((p) => join(state, `mpv-${p.pid}.sock`));
  assert.ok(await until(() => socks.every((s) => existsSync(s)), 5000), 'both players opened their sockets');
  assert.equal(spawnSync(dots, ['theme', 'blueprint'], { env: isolated(state) }).status, 0);
  const ink = (name) => '#ff' + JSON.parse(readFileSync(join(state, 'dots/theme-out/shell.json'), 'utf8')).color.ink.slice(1).toLowerCase();
  const blue = ink();
  for (const s of socks) assert.equal((await mpvAsk(s, ['get_property', 'osd-color'])).toLowerCase(), blue);
  const t0 = Date.now();
  assert.equal(spawnSync(dots, ['theme', 'paper'], { env: isolated(state) }).status, 0);
  const paper = ink();
  assert.notEqual(paper, blue);
  for (const s of socks) {
    assert.ok(await until(async () => (await mpvAsk(s, ['get_property', 'osd-color'])).toLowerCase() === paper, 1000), s);
    assert.equal((await mpvAsk(s, ['get_property', 'script-opts']))['osc-background_color'], '#faf6ec');
  }
  assert.ok(Date.now() - t0 <= 1000, `${Date.now() - t0} ms`);
  assert.equal(readFileSync(join(state, 'dots/theme-out/notice'), 'utf8'), 'theme paper: gsettings did not reload\n');
  for (const s of socks) await mpvAsk(s, ['quit']).catch(() => {});
  assert.ok(await until(() => socks.every((s) => !existsSync(s)), 5000), 'both sockets are gone after quit');
  assert.equal(spawnSync(dots, ['theme', 'artboard'], { env: isolated(state) }).status, 0);
});

// A crash runs no shutdown hook, so its socket stays; the next player and the next switch must not trip on it.
test('a socket left by a killed mpv is removed by the next switch, which still reaches the live player', { skip: !hasMpv }, async (t) => {
  const state = mkdtempSync(join(tmpdir(), 'dots-mpv-'));
  t.after(() => rmSync(state, { recursive: true, force: true }));
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
  assert.equal(spawnSync(dots, ['theme', 'blueprint'], { env: isolated(state) }).status, 0);
  assert.equal(existsSync(deadSock), false);
  assert.equal((await mpvAsk(liveSock, ['get_property', 'osd-color'])).toLowerCase(), '#ffd6f4f8');
  assert.equal(readFileSync(join(state, 'dots/theme-out/notice'), 'utf8'), 'theme blueprint: gsettings did not reload\n');
});


// A player started with its own --input-ipc-server keeps it; only a socket named by a dead pid is swept.
test('a switch leaves a socket not named by a pid, such as a player given its own', async (t) => {
  const state = mkdtempSync(join(tmpdir(), 'dots-mpv-'));
  t.after(() => rmSync(state, { recursive: true, force: true }));
  const own = join(state, 'mpv-music.sock');
  const server = createServer(() => {}).listen(own);
  t.after(() => server.close());
  await new Promise((r) => server.once('listening', r));
  assert.equal(spawnSync(dots, ['theme', 'blueprint'], { env: isolated(state) }).status, 0);
  assert.ok(existsSync(own), 'mpv-music.sock is still there');
});
