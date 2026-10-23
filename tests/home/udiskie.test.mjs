// udiskie mounts a USB drive under /run/media/$USER as it is plugged in, which Files lists under DRIVES.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

const repo = new URL('../../', import.meta.url).pathname;
const read = (f) => readFileSync(join(repo, f), 'utf8');

test('udiskie runs without a tray, started with the graphical session, and ships as a package', () => {
  const unit = read('home/dot_config/systemd/user/udiskie.service');
  assert.match(unit, /^ExecStart=\/usr\/bin\/udiskie --automount --no-tray$/m);
  assert.match(unit, /^PartOf=graphical-session\.target$/m);
  assert.match(unit, /^WantedBy=graphical-session\.target$/m);
  assert.equal(read('home/dot_config/systemd/user/graphical-session.target.wants/symlink_udiskie.service').trim(), '../udiskie.service');
  assert.match(read('packages.toml'), /^name = "udiskie"$/m);
});
