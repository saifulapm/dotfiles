// mpv.conf renders per machine, and a real mpv started on it, with a scratch HOME, takes the theme fragment it includes.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawn, spawnSync } from 'node:child_process';
import { existsSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { connect } from 'node:net';

const repo = new URL('../../', import.meta.url).pathname;
const conf = readFileSync(join(repo, 'home/dot_config/mpv/mpv.conf.tmpl'), 'utf8');

function render(machine) {
  const home = realpathSync(mkdtempSync(join(tmpdir(), 'dots-mpv-')));
  writeFileSync(join(home, 'chezmoi.toml'), `[data]\nmachine = "${machine}"\n`);
  const r = spawnSync('chezmoi', ['--config', join(home, 'chezmoi.toml'), '--source', repo, 'execute-template'], { input: conf, encoding: 'utf8', env: { PATH: process.env.PATH, HOME: home } });
  assert.equal(r.status, 0, r.stderr);
  return { home, text: r.stdout };
}
const opts = (text) => text.split('\n').filter((l) => l && !l.startsWith('#'));

test('every machine plays on gpu-next with display-resample and interpolation, and saves its place on quit', () => {
  for (const m of ['macbook-m2', 'mac-mini-m2', 'nuc']) {
    const o = opts(render(m).text);
    for (const l of ['save-position-on-quit=yes', 'vo=gpu-next', 'video-sync=display-resample', 'interpolation=yes', 'tscale=oversample', 'include=~/.local/state/dots/theme-out/mpv.conf']) assert.ok(o.includes(l), `${m}: ${l}`);
  }
});

// Zero-copy vaapi draws corrupt frames on the Macs' decoder, and vaapi-copy only pays for HEVC there.
test('the Macs decode only HEVC in hardware, through vaapi-copy; the NUC decodes through vaapi', () => {
  for (const m of ['macbook-m2', 'mac-mini-m2']) {
    const o = opts(render(m).text);
    assert.deepEqual(o.filter((l) => l.startsWith('hwdec')), ['hwdec=vaapi-copy', 'hwdec-codecs=hevc'], m);
  }
  assert.deepEqual(opts(render('nuc').text).filter((l) => l.startsWith('hwdec')), ['hwdec=vaapi']);
});

function ask(sock, command) {
  return new Promise((resolve, reject) => {
    const c = connect(sock);
    let buf = '';
    c.on('data', (d) => {
      buf += d;
      if (buf.includes('\n')) {
        c.end();
        resolve(JSON.parse(buf.split('\n')[0]));
      }
    });
    c.on('error', reject);
    c.write(JSON.stringify({ command }) + '\n');
  });
}

async function until(f, ms) {
  const end = Date.now() + ms;
  while (!f()) {
    if (Date.now() > end) return false;
    await new Promise((r) => setTimeout(r, 50));
  }
  return true;
}

for (const name of ['paper', 'blueprint', 'artboard']) {
  test(`a new mpv in ${name} draws its OSD and OSC in the rendered colours`, { skip: !spawnSync('sh', ['-c', 'command -v mpv']).stdout.length }, async (t) => {
    const { home, text } = render('macbook-m2');
    t.after(() => rmSync(home, { recursive: true, force: true }));
    mkdirSync(join(home, '.config/mpv'), { recursive: true });
    writeFileSync(join(home, '.config/mpv/mpv.conf'), text);
    const state = join(home, '.local/state');
    const r = spawnSync('node', [join(repo, 'shell/lib/theme-render.mjs'), name], { env: { PATH: process.env.PATH, XDG_STATE_HOME: state }, encoding: 'utf8' });
    assert.equal(r.status, 0, r.stderr);
    const fragment = readFileSync(join(state, 'dots/theme-out/mpv.conf'), 'utf8');
    const want = (k) => fragment.match(new RegExp(`^${k}="([^"]+)"$`, 'm'))[1];
    const sock = join(home, 's');
    const env = { PATH: process.env.PATH, HOME: home, XDG_CONFIG_HOME: join(home, '.config'), XDG_STATE_HOME: state, XDG_RUNTIME_DIR: home };
    const mpv = spawn('mpv', ['--idle', '--no-video', '--no-terminal', `--input-ipc-server=${sock}`], { env, stdio: 'ignore' });
    t.after(() => mpv.kill());
    assert.ok(await until(() => existsSync(sock), 5000), 'mpv opened its socket');
    // mpv answers a colour with its alpha first: #FFrrggbb.
    const color = (await ask(sock, ['get_property', 'osd-color'])).data;
    assert.equal(color.toLowerCase(), '#ff' + want('osd-color').slice(1));
    const so = (await ask(sock, ['get_property', 'script-opts'])).data;
    assert.equal(so['osc-background_color'], fragment.match(/osc-background_color=(#[0-9a-f]{6})/)[1]);
    assert.equal((await ask(sock, ['get_property', 'osd-font'])).data, want('osd-font'));
  });
}
