// The touchpad: niri's own swipes, dots-gestures' four-finger pinches, and the two hot corners.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

const repo = new URL('../../', import.meta.url).pathname;
const read = (f) => readFileSync(join(repo, f), 'utf8');

// dots-call finds the shell by WAYLAND_DISPLAY and niri msg by NIRI_SOCKET, which the user manager has only once niri runs, so niri starts the unit.
test('niri starts dots-gestures, built at apply, with the repo bin on its PATH for dots-call', () => {
  const unit = read('home/dot_config/systemd/user/dots-gestures.service');
  assert.match(unit, /^ExecStart=%h\/\.local\/bin\/dots-gestures$/m);
  assert.match(unit, /^Environment=PATH=%h\/Codes\/dotfiles\/bin:\/usr\/bin:\/bin$/m);
  assert.match(unit, /^PartOf=graphical-session\.target$/m);
  assert.match(read('home/dot_config/niri/config.kdl'), /^spawn-at-startup "systemctl" "--user" "start" "dots-gestures\.service"$/m);
  const script = read('home/.chezmoiscripts/run_onchange_after_13-gestures.sh.tmpl');
  assert.match(script, /^# watcher source hash: \{\{ joinPath \.chezmoi\.workingTree "bin\/dots-gestures\.c" \| include \| sha256sum \}\}$/m);
  assert.match(script, /gcc -O2 -Wall -o "\$HOME\/\.local\/bin\/dots-gestures" .*dots-gestures\.c.* -linput -ludev/);
  for (const name of ['libinput-devel', 'systemd-devel']) assert.match(read('packages.toml'), new RegExp(`^name = "${name}"$`, 'm'), name);
});

test('libinput-gestures is gone, and a machine that had it loses its links', () => {
  assert.doesNotMatch(read('versions.toml'), /libinput-gestures/);
  assert.doesNotMatch(read('home/dot_config/niri/config.kdl'), /libinput-gestures/);
  const removed = read('home/.chezmoiremove').split('\n');
  for (const f of ['.config/libinput-gestures.conf', '.config/systemd/user/libinput-gestures.service', '.local/bin/libinput-gestures']) assert.ok(removed.includes(f), f);
  assert.match(read('bin/dots-cutover'), /\blibinput-gestures\.service\b/);
});

// niri's hot corners can only toggle the overview; the shell's top-right corner opens Notes.
test('only the bottom-left hot corner is niri\'s, in the live session and the nested one', () => {
  assert.match(read('home/dot_config/niri/gestures.kdl'), /^gestures \{\n {4}hot-corners \{\n {8}bottom-left\n {4}\}\n\}$/m);
  assert.match(read('home/dot_config/niri/config.kdl'), /^include "gestures\.kdl"$/m);
  assert.match(read('dev/niri-dev.kdl'), /^include "\.\.\/home\/dot_config\/niri\/gestures\.kdl"$/m);
});
