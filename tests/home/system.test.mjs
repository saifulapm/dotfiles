// Root steps v1 had and v2 brings back: ydotoold with its uinput rule, and swap with zswap on zstd.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

const repo = new URL('../../', import.meta.url).pathname;
const read = (f) => readFileSync(join(repo, f), 'utf8');

test('ydotoold runs as the user at login, on a socket the user owns', () => {
  const unit = read('home/dot_config/systemd/user/ydotoold.service');
  assert.match(unit, /^ExecStart=\/usr\/bin\/ydotoold --socket-path=%t\/\.ydotool_socket --socket-own=%U:%G$/m);
  assert.match(unit, /^WantedBy=default\.target$/m);
  assert.equal(read('home/dot_config/systemd/user/default.target.wants/symlink_ydotoold.service').trim(), '../ydotoold.service');
});

test('the input group may open /dev/uinput, and the rule is installed whenever it changes', () => {
  assert.match(read('system/udev/rules.d/60-uinput-input-group.rules'), /^KERNEL=="uinput", GROUP="input", MODE="0660"/);
  const script = read('home/.chezmoiscripts/run_onchange_after_40-ydotool.sh.tmpl');
  assert.match(script, /^# uinput rule hash: \{\{ .*60-uinput-input-group\.rules.* sha256sum \}\}$/m);
  assert.match(script, /root install -D -m 0644 "\$rule" \/etc\/udev\/rules\.d\/60-uinput-input-group\.rules/);
});

test('zswap compresses with zstd from boot, and swap adds up to 16 G', () => {
  assert.equal(read('system/modules-load.d/zstd.conf'), 'zstd\n');
  assert.match(read('system/tmpfiles.d/zswap.conf'), /^w \/sys\/module\/zswap\/parameters\/compressor - - - - zstd$/m);
  const script = read('home/.chezmoiscripts/run_onchange_after_41-memory.sh.tmpl');
  assert.match(script, /\(\(have >= 16\)\) && exit 0/);
  assert.match(script, /swapon --fixpgsz/);
});

test('systemd-oomd is masked on every machine, before the container exit, and swap is left as it is', () => {
  const script = read('home/.chezmoiscripts/run_onchange_after_41-memory.sh.tmpl');
  const mask = script.indexOf('root systemctl mask systemd-oomd.service systemd-oomd.socket');
  assert.ok(mask > 0, 'the memory script masks both oomd units');
  assert.ok(mask < script.indexOf('systemd-detect-virt'), 'the mask runs in a container too');
  assert.doesNotMatch(script, /swapoff|zram-generator/);
  assert.match(read('home/.chezmoiremove'), /^\.config\/systemd\/user\/slice\.d\/50-oomd-patient\.conf$/m);
});

test('the diagnose-crash skill says oomd is masked and swap is files plus zswap', () => {
  const skill = read('home/dot_claude/skills/diagnose-crash/SKILL.md');
  assert.doesNotMatch(skill, /95%|swap on zram/);
  assert.match(skill, /systemd-oomd is masked/);
  assert.match(skill, /zswap/);
});
