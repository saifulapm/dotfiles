// The chezmoi source applied to a scratch home opens each kind of file in its app, and WirePlumber connects a known headset's A2DP.
import { before, after, test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const repo = new URL('../../', import.meta.url).pathname.replace(/\/$/, '');
let root, home, env;

before(() => {
  root = realpathSync(mkdtempSync(join(tmpdir(), 'desktop-')));
  home = join(root, 'home');
  mkdirSync(home);
  writeFileSync(join(root, 'chezmoi.toml'), `sourceDir = "${repo}"\nmode = "symlink"\n[data]\n    machine = "test"\n`);
  env = {
    // xdg-mime passes over a default whose Exec is not on PATH, and kak.desktop and mail-open.desktop run commands from the repo's bin/.
    PATH: `${repo}/bin:${process.env.PATH}`,
    HOME: home,
    XDG_CONFIG_HOME: join(home, '.config'),
    XDG_DATA_HOME: join(home, '.local/share'),
    XDG_DATA_DIRS: '/usr/share',
    XDG_STATE_HOME: join(home, '.local/state'),
  };
  const applied = spawnSync('chezmoi', ['--config', join(root, 'chezmoi.toml'), '--source', repo, '--destination', home, 'apply', '--exclude', 'scripts,encrypted'], { env, encoding: 'utf8' });
  assert.equal(applied.status, 0, applied.stderr);
});

after(() => rmSync(root, { recursive: true, force: true }));

test('xdg-mime opens PDFs, images, video, text and links in their apps', () => {
  const want = {
    'application/pdf': 'org.pwmt.zathura.desktop',
    'image/png': 'imv.desktop',
    'image/jpeg': 'imv.desktop',
    'video/mp4': 'mpv.desktop',
    'audio/mpeg': 'mpv.desktop',
    'text/plain': 'kak.desktop',
    'text/markdown': 'kak.desktop',
    'x-scheme-handler/https': 'chromium-browser.desktop',
    'text/html': 'chromium-browser.desktop',
  };
  for (const [type, app] of Object.entries(want)) {
    const r = spawnSync('xdg-mime', ['query', 'default', type], { env, encoding: 'utf8' });
    assert.equal(r.stdout.trim(), app, type);
  }
});

test('kak.desktop opens the files in kak in a themed foot window', () => {
  const entry = readFileSync(join(home, '.local/share/applications/kak.desktop'), 'utf8');
  assert.match(entry, /^Exec=dots-foot kak %F$/m);
});

test('a mailto link opens mail-open', () => {
  const r = spawnSync('xdg-mime', ['query', 'default', 'x-scheme-handler/mailto'], { env, encoding: 'utf8' });
  assert.equal(r.stdout, 'mail-open.desktop\n');
  const entry = readFileSync(join(home, '.local/share/applications/mail-open.desktop'), 'utf8');
  assert.match(entry, /^Exec=mail-open$/m);
  assert.match(entry, /^MimeType=x-scheme-handler\/mailto;$/m);
});

test('WirePlumber connects A2DP and retries HFP on attach, with a dummy AVRCP player and no SBC-XQ', () => {
  const r = spawnSync('spa-json-dump', [join(home, '.config/wireplumber/wireplumber.conf.d/bluetooth-a2dp-autoconnect.conf')], { encoding: 'utf8' });
  assert.equal(r.status, 0, r.stderr);
  const conf = JSON.parse(r.stdout);
  assert.deepEqual(conf['monitor.bluez.properties'], {
    'bluez5.roles': ['a2dp_source', 'hfp_ag'],
    'bluez5.dummy-avrcp-player': true,
    'bluez5.codecs': ['sbc', 'aac'],
  });
  assert.deepEqual(conf['monitor.bluez.rules'], [
    {
      matches: [{ 'device.name': '~bluez_card.*' }],
      actions: { 'update-props': { 'bluez5.auto-connect': ['a2dp_sink', 'hfp_hf'], 'session.dont-restore-off-profile': true } },
    },
  ]);
});
