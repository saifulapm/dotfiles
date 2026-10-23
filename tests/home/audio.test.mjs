// The NUC's HDA audio stays awake; a machine without snd_hda_intel, as the Macs, gets neither half and loses v1's keepalive link.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { existsSync, lstatSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, symlinkSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const repo = new URL('../../', import.meta.url).pathname;
const read = (f) => readFileSync(join(repo, f), 'utf8');
const hda = existsSync('/sys/module/snd_hda_intel');

test(`the wireplumber keepalive follows snd_hda_intel (${hda ? 'loaded' : 'not loaded'} here), replacing v1's link`, () => {
  const root = realpathSync(mkdtempSync(join(tmpdir(), 'audio-test-')));
  const home = join(root, 'home');
  const dir = join(home, '.config/wireplumber/wireplumber.conf.d');
  mkdirSync(dir, { recursive: true });
  writeFileSync(join(root, 'v1-keepalive.conf'), '# v1\n');
  symlinkSync(join(root, 'v1-keepalive.conf'), join(dir, 'sink-keepalive.conf'));
  const config = join(root, 'chezmoi.toml');
  writeFileSync(config, `sourceDir = "${repo}"\nmode = "symlink"\n\n[data]\n    machine = "test"\n`);
  const r = spawnSync('chezmoi', ['--config', config, '--source', repo, '--destination', home, 'apply', '--force', join(home, '.config/wireplumber')], {
    encoding: 'utf8',
    env: { PATH: process.env.PATH, HOME: home },
  });
  assert.equal(r.status, 0, r.stderr);
  const target = join(dir, 'sink-keepalive.conf');
  if (hda) {
    const conf = readFileSync(target, 'utf8');
    assert.match(conf, /session\.suspend-timeout-seconds = 0/);
    assert.match(conf, /dither\.noise = 2/);
    assert.match(conf, /node\.name = "~bluez_output\.\*"/);
  } else {
    assert.equal(existsSync(target) || lstatSync(target, { throwIfNoEntry: false }) !== undefined, false, 'the keepalive is gone');
  }
});

test('power_save=0 is installed only where snd_hda_intel is loaded, and never in a container', () => {
  assert.match(read('system/modprobe.d/hda-power-save.conf'), /^options snd_hda_intel power_save=0$/m);
  const script = read('home/.chezmoiscripts/run_onchange_after_42-tunings.sh.tmpl');
  assert.match(script, /^# tunings source hashes:.*modprobe\.d\/hda-power-save\.conf.*sha256sum/m);
  const gate = script.indexOf('[[ -d /sys/module/snd_hda_intel ]]');
  const install = script.indexOf('/etc/modprobe.d/hda-power-save.conf');
  assert.ok(gate > 0 && install > gate, 'the option is installed only past the snd_hda_intel gate');
  assert.ok(script.indexOf('systemd-detect-virt -q --container') < install, 'a container stops before the option');
  assert.match(script, /printf 0 \| root tee \/sys\/module\/snd_hda_intel\/parameters\/power_save/);
});
