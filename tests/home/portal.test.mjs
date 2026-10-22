// The shell's file picker is registered as niri's FileChooser portal, with gtk behind it, and v1's qshell registration goes.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

const repo = new URL('../../', import.meta.url).pathname;
const read = (f) => readFileSync(join(repo, f), 'utf8');
const bus = 'org.freedesktop.impl.portal.desktop.dots';

test('dots.portal declares the FileChooser backend for niri on the dots bus name', () => {
  const portal = read('system/xdg-desktop-portal/portals/dots.portal');
  assert.match(portal, /^\[portal\]$/m);
  assert.match(portal, new RegExp(`^DBusName=${bus.replaceAll('.', '\\.')}$`, 'm'));
  assert.match(portal, /^Interfaces=org\.freedesktop\.impl\.portal\.FileChooser;$/m);
  assert.match(portal, /^UseIn=niri$/m);
});

test('D-Bus starts bin/dots-portal from the working tree on the first request', () => {
  const service = read(`home/dot_local/share/dbus-1/services/${bus}.service.tmpl`);
  assert.match(service, /^\[D-BUS Service\]$/m);
  assert.match(service, new RegExp(`^Name=${bus.replaceAll('.', '\\.')}$`, 'm'));
  assert.match(service, /^Exec=\{\{ joinPath \.chezmoi\.workingTree "bin\/dots-portal" \}\}$/m);
});

test("niri's portals.conf asks dots for files, then gtk, and keeps niri's shipped lines", () => {
  const conf = read('home/dot_config/xdg-desktop-portal/niri-portals.conf');
  assert.match(conf, /^org\.freedesktop\.impl\.portal\.FileChooser=dots;gtk;$/m);
  // xdg-desktop-portal reads the first config it finds and merges nothing, so niri's own lines are repeated.
  for (const line of ['[preferred]', 'default=gnome;gtk;', 'org.freedesktop.impl.portal.Access=gtk;', 'org.freedesktop.impl.portal.Notification=gtk;', 'org.freedesktop.impl.portal.Secret=gnome-keyring;']) {
    assert.ok(conf.split('\n').includes(line), line);
  }
});

test('install puts dots.portal where xdg-desktop-portal reads it, drops qshell.portal and restarts the frontend on a change', () => {
  const script = read('home/.chezmoiscripts/run_onchange_after_44-portal.sh.tmpl');
  assert.match(script, /^# portal hashes: \{\{ .*"system\/xdg-desktop-portal\/portals\/dots\.portal".*sha256sum \}\} \{\{ .*"dot_config\/xdg-desktop-portal\/niri-portals\.conf".*sha256sum \}\}$/m);
  assert.match(script, /root install -D -m 0644 .*"system\/xdg-desktop-portal\/portals\/dots\.portal".* \/usr\/share\/xdg-desktop-portal\/portals\/dots\.portal/);
  assert.match(script, /root rm -f \/usr\/share\/xdg-desktop-portal\/portals\/qshell\.portal/);
  assert.match(script, /systemctl --user restart xdg-desktop-portal\.service/);
});

test("v1's qshell activation file is removed, and gtk's chooser is installed as the fallback", () => {
  assert.ok(read('home/.chezmoiremove').split('\n').includes('.local/share/dbus-1/services/org.freedesktop.impl.portal.desktop.qshell.service'));
  assert.match(read('packages.toml'), /^name = "xdg-desktop-portal-gtk"$/m);
});
