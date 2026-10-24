// libinput-gestures gives the touchpad the four-finger pinches niri cannot bind: in opens the launcher, out the notification centre.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

const repo = new URL('../../', import.meta.url).pathname;
const read = (f) => readFileSync(join(repo, f), 'utf8');

test('a four-finger pinch in opens the launcher and out the notification centre, as Mod+Space and Mod+A do', () => {
  const gestures = read('home/dot_config/libinput-gestures.conf').split('\n').filter((l) => l && !l.startsWith('#'));
  assert.deepEqual(gestures, ['gesture pinch in 4 dots-call launcher toggle', 'gesture pinch out 4 dots-call notifs toggle']);
  const binds = read('home/dot_config/niri/binds.kdl');
  assert.match(binds, /Mod\+Space .*\{ spawn "dots-call" "launcher" "toggle"; \}/);
  assert.match(binds, /Mod\+A .*\{ spawn "dots-call" "notifs" "toggle"; \}/);
});

// dots-call finds the shell by WAYLAND_DISPLAY, which the user manager has only once niri runs, so niri starts the unit.
test('niri starts libinput-gestures from ~/.local/bin, with the repo bin on its PATH for dots-call', () => {
  const unit = read('home/dot_config/systemd/user/libinput-gestures.service');
  assert.match(unit, /^ExecStart=%h\/\.local\/bin\/libinput-gestures$/m);
  assert.match(unit, /^Environment=PATH=%h\/Codes\/dotfiles\/bin:\/usr\/bin:\/bin$/m);
  assert.match(unit, /^PartOf=graphical-session\.target$/m);
  assert.match(read('home/dot_config/niri/config.kdl'), /^spawn-at-startup "systemctl" "--user" "start" "libinput-gestures\.service"$/m);
});

test('libinput-gestures is a commit pin installed into ~/.local/bin', () => {
  const versions = read('versions.toml');
  assert.match(versions, /name = "libinput-gestures"\nversion = "[0-9a-f]{40}"\nrepo = "bulletmark\/libinput-gestures"\ntrack = "commit"/);
  const script = read('home/.chezmoiscripts/run_onchange_after_29-pin-libinput-gestures.sh.tmpl');
  assert.match(script, /install -m 0755 .*libinput-gestures.* "\$HOME\/\.local\/bin\/libinput-gestures"/);
});
