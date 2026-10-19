import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

// just dev runs the shell as a transient unit, so its settings must match the real unit's.
const root = new URL('../..', import.meta.url).pathname;
const unit = readFileSync(root + 'home/dot_config/systemd/user/dots-shell.service', 'utf8');
const dev = readFileSync(root + 'bin/dots-dev-shell', 'utf8');

const unitProps = (key) => [...unit.matchAll(new RegExp(`^${key}=(.*)$`, 'gm'))].map((m) => m[1]);

test('the real unit restarts after 500 ms and never gives up', () => {
  assert.deepEqual(unitProps('Restart'), ['always']);
  assert.deepEqual(unitProps('RestartSec'), ['500ms']);
  assert.deepEqual(unitProps('StartLimitIntervalSec'), ['0']);
});

test('the dev unit restarts like the real one', () => {
  for (const p of ['Restart=always', 'RestartSec=500ms', 'StartLimitIntervalSec=0']) assert.match(dev, new RegExp(`-p ${p}\\b`));
});

// Each unit's shell dir is its own: the live config link, or the checkout or copy just dev runs.
const shellDir = (env) => env.replace('%h/.config/quickshell/', '<shell>/').replace('$QS_CONFIG_PATH/', '<shell>/');

test('the dev unit sets the same environment as the real one', () => {
  const real = unitProps('Environment').map(shellDir).sort();
  const devEnv = [...dev.matchAll(/-E (\w+=\S*)/g)].map((m) => shellDir(m[1])).sort();
  assert.deepEqual(devEnv, real);
  assert.ok(real.includes('QSG_RENDER_LOOP=basic'));
});

test("both units give the shell its own fontconfig, from the shell dir it runs", () => {
  assert.deepEqual(unitProps('Environment').filter((e) => e.startsWith('FONTCONFIG_FILE=')), ['FONTCONFIG_FILE=%h/.config/quickshell/fonts.conf']);
  assert.match(dev, /-E FONTCONFIG_FILE=\$QS_CONFIG_PATH\/fonts\.conf\b/);
});

const userUnit = (name) => readFileSync(root + 'home/dot_config/systemd/user/' + name, 'utf8');
const props = (text, key) => [...text.matchAll(new RegExp(`^${key}=(.*)$`, 'gm'))].map((m) => m[1]);
const syncCmd = (args) => `{{ joinPath .chezmoi.workingTree "bin/dots" }} sync${args}`;

test('the sync timer runs dots sync 3 min after boot and then every 15 min', () => {
  const timer = userUnit('dots-sync.timer');
  assert.deepEqual(props(timer, 'OnBootSec'), ['3min']);
  assert.deepEqual(props(timer, 'OnUnitActiveSec'), ['15min']);
  const service = userUnit('dots-sync.service.tmpl');
  assert.deepEqual(props(service, 'Type'), ['oneshot']);
  assert.deepEqual(props(service, 'ExecStart'), [syncCmd('')]);
});

test('a change to the notes or goals store runs dots sync --only for that unit', () => {
  for (const unit of ['notes', 'goals']) {
    const path = userUnit(`dots-sync-${unit}.path`);
    assert.deepEqual(props(path, 'PathChanged'), [`%h/.local/share/dots/${unit}`]);
    assert.deepEqual(props(path, 'MakeDirectory'), ['yes']);
    assert.deepEqual(props(userUnit(`dots-sync-${unit}.service.tmpl`), 'ExecStart'), [syncCmd(` --only ${unit}`)]);
  }
});

test('niri starts the sync timer and both path units at login', () => {
  const niri = readFileSync(root + 'home/dot_config/niri/config.kdl', 'utf8');
  for (const u of ['dots-sync.timer', 'dots-sync-notes.path', 'dots-sync-goals.path']) {
    assert.match(niri, new RegExp(`^spawn-at-startup "systemctl" "--user" "start" "${u.replace('.', '\\.')}"$`, 'm'));
  }
});

// The motion slowdown is for nested checks only, so the live shell always moves at its theme's speed.
test('only the dev unit carries the motion slowdown', () => {
  assert.doesNotMatch(unit, /DOTS_MOTION_SLOWDOWN/);
  assert.match(dev, /-E DOTS_MOTION_SLOWDOWN\b/);
  assert.match(readFileSync(root + 'bin/dots-dev', 'utf8'), /^export DOTS_MOTION_SLOWDOWN=\$\{DOTS_MOTION_SLOWDOWN:-1\}$/m);
});
