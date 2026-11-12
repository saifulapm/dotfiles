import { after, describe, test } from 'node:test';
import assert from 'node:assert/strict';
import { spawn, spawnSync } from 'node:child_process';
import { once } from 'node:events';
import { closeSync, cpSync, existsSync, mkdirSync, mkdtempSync, openSync, readFileSync, readSync, readdirSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

// Every channel dots colorscheme reloads points into the temp dir, so a name that slipped through still reaches nothing live.
const dots = new URL('../../bin/dots', import.meta.url).pathname;
const repo = new URL('../..', import.meta.url).pathname;

function isolated(state) {
  const env = Object.assign({}, process.env, {
    XDG_STATE_HOME: state, WAYLAND_DISPLAY: '', DBUS_SESSION_BUS_ADDRESS: `unix:path=${state}/no-bus`,
    TMUX_TMPDIR: state, DCONF_PROFILE: `${state}/no-profile`, XDG_RUNTIME_DIR: state,
    DOTS_AGENT_HOME: `${state}/agents`,
  });
  delete env.TMUX;
  return env;
}

// A switch spends most of its time waiting on node, jq and its reloads, so the tests below run their switches side by side.
function run(cmd, args, opts) {
  return new Promise((resolve, reject) => {
    const p = spawn(cmd, args, Object.assign({}, opts, { stdio: ['ignore', 'pipe', 'pipe'] }));
    let stdout = '';
    let stderr = '';
    p.stdout.setEncoding('utf8').on('data', (d) => (stdout += d));
    p.stderr.setEncoding('utf8').on('data', (d) => (stderr += d));
    p.on('error', reject);
    p.on('close', (status) => resolve({ status, stdout, stderr }));
  });
}

const artboard = readFileSync(join(repo, 'colorschemes/artboard.toml'), 'utf8');
// A dark scheme under its own name, and Artboard with grey ink on white, which the contrast check refuses.
const night = readFileSync(join(repo, 'colorschemes/github-dark.toml'), 'utf8').replace('name = "github-dark"', 'name = "night"');
const faint = artboard.replace('name = "artboard"', 'name = "faint"').replace('ink = "#15171B"', 'ink = "#9AA0A6"');

// bin/dots finds its repo from its own path, so a copy of it renders the schemes beside it, the test's own among them; the tests only read the copy, so they share one.
const root = mkdtempSync(join(tmpdir(), 'dots-root-'));
after(() => rmSync(root, { recursive: true, force: true }));
for (const d of ['bin/dots', 'shell/lib', 'shell/newtab', 'colorschemes']) cpSync(join(repo, d), join(root, d), { recursive: true });
writeFileSync(join(root, 'colorschemes/night.toml'), night);
writeFileSync(join(root, 'colorschemes/faint.toml'), faint);

function fixture(t) {
  const state = mkdtempSync(join(tmpdir(), 'dots-state-'));
  t.after(() => rmSync(state, { recursive: true, force: true }));
  return { dots: join(root, 'bin/dots'), state };
}

function snapshot(dir) {
  return Object.fromEntries(readdirSync(dir, { recursive: true }).sort().map((f) => [f, statSync(join(dir, f)).isFile() ? readFileSync(join(dir, f), 'utf8') : 'dir']));
}

describe('dots colorscheme', { concurrency: true }, () => {
  test('dots colorscheme artboard saves artboard and renders it', async (t) => {
    const state = mkdtempSync(join(tmpdir(), 'dots-switch-'));
    t.after(() => rmSync(state, { recursive: true, force: true }));
    const r = await run(dots, ['colorscheme', 'artboard'], { env: isolated(state) });
    assert.equal(r.status, 0, r.stderr);
    assert.equal(readFileSync(join(state, 'dots/theme'), 'utf8'), 'artboard\n');
    assert.equal(JSON.parse(readFileSync(join(state, 'dots/theme-out/shell.json'), 'utf8')).name, 'artboard');
  });

  test('an unknown colorscheme is refused, keeps the current one and says why in the notice each time', async (t) => {
    const state = mkdtempSync(join(tmpdir(), 'dots-nope-'));
    t.after(() => rmSync(state, { recursive: true, force: true }));
    assert.equal((await run(dots, ['colorscheme', 'artboard'], { env: isolated(state) })).status, 0);
    const out = join(state, 'dots/theme-out');
    const before = snapshot(out);
    delete before.notice;
    for (let i = 0; i < 2; i++) {
      writeFileSync(join(out, 'notice'), 'colorscheme artboard: gsettings did not reload\n');
      const r = await run(dots, ['colorscheme', 'nope'], { env: isolated(state) });
      assert.equal(r.status, 1);
      assert.equal(r.stderr, 'colorscheme nope: no such colorscheme\n');
      assert.equal(readFileSync(join(out, 'notice'), 'utf8'), 'colorscheme nope: no such colorscheme\n');
    }
    assert.equal(readFileSync(join(state, 'dots/theme'), 'utf8'), 'artboard\n');
    const after = snapshot(out);
    delete after.notice;
    assert.deepEqual(after, before);
  });

  test('a colorscheme whose ink is too faint on its surface is refused, and the current one stays', async (t) => {
    const { dots, state } = fixture(t);
    assert.equal((await run(dots, ['colorscheme', 'artboard'], { env: isolated(state) })).status, 0);
    const shell = readFileSync(join(state, 'dots/theme-out/shell.json'), 'utf8');
    const r = await run(dots, ['colorscheme', 'faint'], { env: isolated(state) });
    assert.equal(r.status, 1);
    assert.match(readFileSync(join(state, 'dots/theme-out/notice'), 'utf8'), /^colorscheme faint: .*contrast/);
    assert.equal(readFileSync(join(state, 'dots/theme'), 'utf8'), 'artboard\n');
    assert.equal(readFileSync(join(state, 'dots/theme-out/shell.json'), 'utf8'), shell);
  });

  // The bench reads ms; start and end let a reader line the switch up against the shell's own frames.
  test('a switch stamps its start, and its end after the last reload returns', async (t) => {
    const state = mkdtempSync(join(tmpdir(), 'dots-stamp-'));
    t.after(() => rmSync(state, { recursive: true, force: true }));
    const bin = join(state, 'bin');
    mkdirSync(bin);
    const env = Object.assign(isolated(state), { PATH: `${bin}:${process.env.PATH}` });
    assert.equal((await run(dots, ['colorscheme', 'artboard'], { env })).status, 0);
    writeFileSync(join(bin, 'gsettings'), '#!/bin/bash\nsleep 0.1\n', { mode: 0o755 });
    const t0 = Date.now() - 500;
    const r = await run(dots, ['colorscheme', 'artboard'], { env: Object.assign(env, { DOTS_SWITCH_T0: String(t0) }) });
    assert.equal(r.status, 0, r.stderr);
    const s = JSON.parse(readFileSync(join(state, 'dots/theme-switch.json'), 'utf8'));
    assert.equal(s.from, 'artboard');
    assert.equal(s.to, 'artboard');
    assert.equal(s.start, t0);
    // Three gsettings calls of 100 ms each run before the end is taken.
    assert.ok(s.end - s.start >= 780, `end ${s.end - s.start} ms after start`);
    assert.ok(s.end <= Date.now());
    assert.equal(s.ms, s.end - s.start);
  });

  test('a switch tells GTK light for a light colorscheme and dark for a dark one', async (t) => {
    const { dots, state } = fixture(t);
    const bin = join(state, 'bin');
    mkdirSync(bin);
    const log = join(state, 'gsettings.log');
    writeFileSync(join(bin, 'gsettings'), `#!/bin/bash\necho "$*" >>${log}\n`, { mode: 0o755 });
    const env = Object.assign(isolated(state), { PATH: `${bin}:${process.env.PATH}` });
    const scheme = () => readFileSync(log, 'utf8').trim().split('\n').filter((l) => l.includes('color-scheme')).pop();
    assert.equal((await run(dots, ['colorscheme', 'artboard'], { env })).status, 0);
    assert.equal(scheme(), 'set org.gnome.desktop.interface color-scheme prefer-light');
    assert.equal((await run(dots, ['colorscheme', 'night'], { env })).status, 0);
    assert.equal(scheme(), 'set org.gnome.desktop.interface color-scheme prefer-dark');
  });

  test('the theme command is gone: it names dots colorscheme and changes nothing', (t) => {
    const state = mkdtempSync(join(tmpdir(), 'dots-old-'));
    t.after(() => rmSync(state, { recursive: true, force: true }));
    const r = spawnSync(dots, ['theme', 'artboard'], { env: isolated(state), encoding: 'utf8' });
    assert.equal(r.status, 1);
    assert.match(r.stderr, /dots colorscheme/);
    assert.deepEqual(readdirSync(state), []);
    const usage = spawnSync(dots, [], { env: isolated(state), encoding: 'utf8' }).stderr;
    assert.match(usage, /dots colorscheme <name>/);
    assert.doesNotMatch(usage, /dots theme/);
  });

  test('a colorscheme name that is not a plain lower-case word is refused and changes nothing', (t) => {
    const state = mkdtempSync(join(tmpdir(), 'dots-name-'));
    t.after(() => rmSync(state, { recursive: true, force: true }));
    for (const name of ['"x', '../artboard', '-x', 'a b', 'Artboard', '', 'ünï', 'a'.repeat(33)]) {
      const env = isolated(state);
      const r = spawnSync(dots, ['colorscheme', name], { env, encoding: 'utf8' });
      assert.equal(r.status, 1, `${JSON.stringify(name)}: ${r.stderr}`);
      assert.match(r.stderr, /dots: (colorscheme .*: not a colorscheme name|usage: dots colorscheme <name>)/);
    }
    assert.deepEqual(readdirSync(state), []);
  });

  // niri, the shell and tmux read fragments while a switch writes them; truncating in place let a reader see half a file.
  test('a switch replaces a changed fragment whole, so a reader of the old one still reads all of it', async (t) => {
    const { dots, state } = fixture(t);
    assert.equal((await run(dots, ['colorscheme', 'artboard'], { env: isolated(state) })).status, 0);
    const path = join(state, 'dots/theme-out/niri.kdl');
    const light = readFileSync(path, 'utf8');
    const fd = openSync(path, 'r');
    assert.equal((await run(dots, ['colorscheme', 'night'], { env: isolated(state) })).status, 0);
    const buf = Buffer.alloc(light.length + 1);
    const n = readSync(fd, buf, 0, buf.length, 0);
    closeSync(fd);
    assert.equal(buf.subarray(0, n).toString(), light);
    assert.notEqual(readFileSync(path, 'utf8'), light);
    assert.deepEqual(readdirSync(join(state, 'dots/theme-out')).filter((f) => f.includes('.tmp')), []);
  });

  // Each reload ran in the background with its status dropped, so an app left on the old colorscheme said nothing.
  test('a switch names the apps that did not reload in the notice the island shows', async (t) => {
    const { dots, state } = fixture(t);
    const notice = () => readFileSync(join(state, 'dots/theme-out/notice'), 'utf8');
    // No session bus refuses gsettings.
    assert.equal((await run(dots, ['colorscheme', 'night'], { env: isolated(state) })).status, 0);
    assert.equal(notice(), 'colorscheme night: gsettings did not reload\n');
    writeFileSync(join(state, 'dots/theme-out/notice'), 'colorscheme night: tmux did not reload\n');
    assert.equal((await run(dots, ['colorscheme', 'artboard'], { env: isolated(state) })).status, 0);
    assert.equal(notice(), 'colorscheme artboard: gsettings did not reload\n');
  });

  // The agents' configs name the theme qshell, and each reloads its file when it changes.
  test('a switch writes the Claude Code, pi and amx themes into the ones installed, and nothing for opencode', async (t) => {
    const { dots, state } = fixture(t);
    const home = join(state, 'agents');
    for (const d of ['.claude', '.config/opencode', '.config/amx']) mkdirSync(join(home, d), { recursive: true });
    assert.equal((await run(dots, ['colorscheme', 'artboard'], { env: isolated(state) })).status, 0);
    const out = (f) => readFileSync(join(state, 'dots/theme-out', f), 'utf8');
    assert.equal(readFileSync(join(home, '.claude/themes/dots.json'), 'utf8'), out('claude.json'));
    assert.deepEqual(readdirSync(join(home, '.config/opencode')), []);
    assert.equal(readFileSync(join(home, '.config/amx/themes/dots.toml'), 'utf8'), out('amx.toml'));
    assert.equal(JSON.parse(out('claude.json')).base, 'light');
    assert.deepEqual(readdirSync(home, { recursive: true }).filter((f) => f.startsWith('.pi')), []);
    assert.equal((await run(dots, ['colorscheme', 'night'], { env: isolated(state) })).status, 0);
    assert.equal(JSON.parse(readFileSync(join(home, '.claude/themes/dots.json'), 'utf8')).base, 'dark');
    mkdirSync(join(home, '.pi/agent'), { recursive: true });
    assert.equal((await run(dots, ['colorscheme', 'artboard'], { env: isolated(state) })).status, 0);
    assert.equal(readFileSync(join(home, '.pi/agent/themes/dots.json'), 'utf8'), out('pi.json'));
  });

  // helix rereads its config, and with it the theme file, on USR1; this hx answers only on a display name of its own, so no real editor, and no other test's switch, reaches it.
  test('a switch sends USR1 to helix on this display, so it rereads its theme', async (t) => {
    const state = mkdtempSync(join(tmpdir(), 'dots-helix-'));
    t.after(() => rmSync(state, { recursive: true, force: true }));
    const bin = join(state, 'bin');
    mkdirSync(bin);
    const got = join(state, 'usr1');
    const env = Object.assign(isolated(state), { WAYLAND_DISPLAY: `dots-test-${process.pid}-helix` });
    writeFileSync(join(bin, 'hx'), `#!/bin/bash\ntrap 'echo got >${got}; exit 0' USR1\necho ready\nwhile :; do sleep 0.05; done\n`, { mode: 0o755 });
    const hx = spawn(join(bin, 'hx'), [], { env, stdio: ['ignore', 'pipe', 'ignore'] });
    t.after(() => hx.kill('SIGKILL'));
    await new Promise((r) => hx.stdout.once('data', r));
    assert.equal((await run(dots, ['colorscheme', 'artboard'], { env })).status, 0);
    for (let i = 0; i < 40 && !existsSync(got); i++) await new Promise((r) => setTimeout(r, 50));
    assert.equal(readFileSync(got, 'utf8'), 'got\n');
  });

  // zathura answers on the session bus as org.pwmt.zathura.PID-<pid>; this busctl stands in for that bus and logs each call, and the nested check drives a real zathura.
  test('a switch has every zathura on the session bus re-source its config', async (t) => {
    const state = mkdtempSync(join(tmpdir(), 'dots-zathura-'));
    t.after(() => rmSync(state, { recursive: true, force: true }));
    const bin = join(state, 'bin');
    mkdirSync(bin);
    const log = join(state, 'busctl.log');
    writeFileSync(join(bin, 'busctl'), `#!/bin/bash
echo "$*" >>${log}
[[ $* == *' list'* ]] && printf '%s\\n' ':1.7 4242 zathura saiful :1.7 - - -' 'org.pwmt.zathura.PID-4242 4242 zathura saiful :1.7 - - -' 'org.pwmt.zathura.PID-77 77 zathura saiful :1.9 - - -' 'org.freedesktop.Notifications 12 qs saiful :1.2 - - -'
exit 0
`, { mode: 0o755 });
    const env = Object.assign(isolated(state), { PATH: `${bin}:${process.env.PATH}` });
    assert.equal((await run(dots, ['colorscheme', 'artboard'], { env })).status, 0);
    const calls = readFileSync(log, 'utf8').trim().split('\n').filter((l) => l.includes(' call '));
    assert.deepEqual(calls.sort(), [
      '--user --timeout=1 call org.pwmt.zathura.PID-4242 /org/pwmt/zathura org.pwmt.zathura SourceConfig',
      '--user --timeout=1 call org.pwmt.zathura.PID-77 /org/pwmt/zathura org.pwmt.zathura SourceConfig',
    ]);
  });

  // imv answers imv-msg on $XDG_RUNTIME_DIR/imv-<pid>.sock; only background changes live. These stand-ins run on a display name of their own, so another test's switch never finds them, and the nested check drives a real imv.
  test('a switch sends each imv on this display its new background', async (t) => {
    const state = mkdtempSync(join(tmpdir(), 'dots-imv-'));
    t.after(() => rmSync(state, { recursive: true, force: true }));
    const bin = join(state, 'bin');
    mkdirSync(bin);
    const log = join(state, 'imv-msg.log');
    writeFileSync(join(bin, 'imv-wayland'), '#!/bin/bash\nwhile :; do sleep 0.05; done\n', { mode: 0o755 });
    writeFileSync(join(bin, 'imv-msg'), `#!/bin/bash\necho "$*" >>${log}\n`, { mode: 0o755 });
    const env = Object.assign(isolated(state), { PATH: `${bin}:${process.env.PATH}`, WAYLAND_DISPLAY: `dots-test-${process.pid}-imv` });
    const imv = spawn(join(bin, 'imv-wayland'), [], { env, stdio: 'ignore' });
    t.after(() => imv.kill('SIGKILL'));
    // The child has run exec once spawn fires, so pgrep finds it by name from here.
    await once(imv, 'spawn');
    assert.equal((await run(dots, ['colorscheme', 'artboard'], { env })).status, 0);
    assert.equal(readFileSync(log, 'utf8'), `${imv.pid} background e4e6ea\n`);
  });
});
