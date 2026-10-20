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
    PATH: process.env.PATH,
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

test('WirePlumber offers A2DP to headsets and connects it on attach', () => {
  const conf = readFileSync(join(home, '.config/wireplumber/wireplumber.conf.d/bluetooth-a2dp-autoconnect.conf'), 'utf8');
  assert.match(conf, /bluez5\.roles = \[ a2dp_source hfp_ag \]/);
  assert.match(conf, /bluez5\.auto-connect = \[ a2dp_sink \]/);
  assert.match(conf, /session\.dont-restore-off-profile = true/);
});
