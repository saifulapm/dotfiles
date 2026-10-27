// nirius: the scratchpad and follow-mode daemon niri's binds talk to, built from its crates.io pin.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

const repo = new URL('../../', import.meta.url).pathname;
const read = (f) => readFileSync(join(repo, f), 'utf8');

// niriusd finds niri by NIRI_SOCKET, which the user manager has only once niri runs, so niri starts the unit.
test('niri starts niriusd, which restarts when it dies', () => {
  const unit = read('home/dot_config/systemd/user/niriusd.service');
  assert.match(unit, /^ExecStart=%h\/\.local\/bin\/niriusd$/m);
  assert.match(unit, /^PartOf=graphical-session\.target$/m);
  assert.match(unit, /^Restart=always$/m);
  assert.match(read('home/dot_config/niri/config.kdl'), /^spawn-at-startup "systemctl" "--user" "start" "niriusd\.service"$/m);
});

test('the nirius pin is the crates.io crate, built into nirius and niriusd, and a running daemon picks the new build up', () => {
  const pin = read('versions.toml').split(/^(?=\[\[)/m).find((b) => /^name = "nirius"$/m.test(b));
  assert.ok(pin, 'versions.toml has a nirius pin');
  assert.match(pin, /^crate = "nirius"$/m);
  assert.match(pin, /^url = "https:\/\/static\.crates\.io\/crates\/nirius\/nirius-\{version\}\.crate"$/m);
  const script = read('home/.chezmoiscripts/run_onchange_after_29-pin-nirius.sh.tmpl');
  assert.match(script, /^pin_cargo "\$pin_tmp\/nirius-\$pin_version" nirius niriusd$/m);
  assert.match(script, /systemctl --user try-restart niriusd\.service/);
});
