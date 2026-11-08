import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { chmodSync, mkdirSync, mkdtempSync, readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { backlights, ddcDisplays, routeOf, ACTIONS, actionCommand, parseSync, syncFailing, syncRows, chargeLimit, chargeCommand } from './control-system.mjs';

test('brightnessctl -m -l lines become backlights with their percent', () => {
  const text = 'apple-panel-bl,backlight,36,7%,509\n228600000.dsi.0,backlight,0,0%,255\n';
  assert.deepEqual(backlights(text), [
    { device: 'apple-panel-bl', percent: 7 },
    { device: '228600000.dsi.0', percent: 0 },
  ]);
  assert.deepEqual(backlights(''), []);
});

test('ddcutil detect --terse gives each external display its number and model', () => {
  const text = 'Display 1\n   I2C bus:  /dev/i2c-4\n   Monitor:  DEL:DELL U2720Q:ABC\n\nInvalid display\n   I2C bus:  /dev/i2c-5\n\nDisplay 2\n   I2C bus:  /dev/i2c-6\n   Monitor:  GSM:LG HDR 4K:XYZ\n';
  assert.deepEqual(ddcDisplays(text), [
    { display: 1, name: 'DELL U2720Q' },
    { display: 2, name: 'LG HDR 4K' },
  ]);
  assert.deepEqual(ddcDisplays('No displays found.\n'), []);
});

test('workflow route prints where questions ring', () => {
  assert.equal(routeOf('route: phone\n'), 'phone');
  assert.equal(routeOf('route: device (macbook-m2)\n'), 'device');
  assert.equal(routeOf('error: hub did not answer\n'), '');
});

test('log out, reboot and power off are the session actions, each a fixed argv', () => {
  assert.deepEqual(ACTIONS.map((a) => a.id), ['lock', 'logout', 'reboot', 'poweroff']);
  assert.deepEqual(actionCommand('reboot'), ['systemctl', 'reboot']);
  assert.deepEqual(actionCommand('poweroff'), ['systemctl', 'poweroff']);
  assert.deepEqual(actionCommand('logout'), ['niri', 'msg', 'action', 'quit', '--skip-confirmation']);
  assert.deepEqual(actionCommand('lock'), ['qs', 'ipc', 'call', 'lock', 'lock']);
  assert.equal(actionCommand('rm'), null);
});

test('sync.json parses to its units, and a missing or broken file to none', () => {
  assert.deepEqual(parseSync('{"notes":{"ok":true,"lastRun":5,"lastOk":5,"error":null}}'), { notes: { ok: true, lastRun: 5, lastOk: 5, error: null } });
  assert.deepEqual(parseSync(''), {});
  assert.deepEqual(parseSync('{"notes":'), {});
  assert.deepEqual(parseSync('[1]'), {});
});

test('Route names the sync state and each failing unit with its error', () => {
  const at = (h, m) => new Date(2026, 9, 19, h, m).getTime();
  assert.deepEqual(syncRows({}), [{ title: 'Sync', detail: 'no rounds yet' }]);
  const good = { notes: { ok: true, lastRun: at(9, 5), lastOk: at(9, 5), error: null }, goals: { ok: true, lastRun: at(14, 2), lastOk: at(14, 2), error: null } };
  assert.equal(syncFailing(good), false);
  assert.deepEqual(syncRows(good), [{ title: 'Sync', detail: 'ok · 14:02' }]);
  const bad = {
    notes: { ok: false, lastRun: at(14, 3), lastOk: at(9, 5), error: 'directory not found' },
    goals: { ok: true, lastRun: at(14, 3), lastOk: at(14, 3), error: null },
    fish: { ok: false, lastRun: at(14, 3), lastOk: null, error: 'Failed to copy: ' + 'x'.repeat(80) },
  };
  assert.equal(syncFailing(bad), true);
  assert.deepEqual(syncRows(bad), [
    { title: 'Sync', detail: '2 failing' },
    { title: 'notes', detail: 'directory not found' },
    { title: 'fish', detail: 'Failed to copy: ' + 'x'.repeat(43) + '…' },
  ]);
});

test('a forged sync.json reads as units Route can draw, never a TypeError', () => {
  const units = parseSync(JSON.stringify({ notes: null, goals: 7, fish: { ok: 'false', lastOk: 'x' }, ssh: { ok: false, error: { a: 1 } }, '<b>x</b>': { ok: true, lastOk: 'soon' } }));
  assert.deepEqual(units, {
    fish: { ok: false, lastRun: null, lastOk: null, error: 'no error recorded' },
    ssh: { ok: false, lastRun: null, lastOk: null, error: 'no error recorded' },
    '<b>x</b>': { ok: true, lastRun: null, lastOk: null, error: null },
  });
  assert.equal(syncFailing(units), true);
  assert.deepEqual(syncRows(units).map((r) => r.detail), ['2 failing', 'no error recorded', 'no error recorded']);
  assert.deepEqual(syncRows(parseSync('{"notes":{"ok":true,"lastOk":"x"}}')), [{ title: 'Sync', detail: 'ok' }]);
});

test("UPower's three properties become the limit while on, 0 while off, -1 where there is none", () => {
  assert.equal(chargeLimit('b true\nb true\nu 80\n'), 80);
  assert.equal(chargeLimit('b true\nb false\nu 80\n'), 0);
  assert.equal(chargeLimit('b false\nb false\nu 100\n'), -1);
  assert.equal(chargeLimit(''), -1);
  assert.equal(chargeLimit('b true\nb true\nu x\n'), -1);
});

test('the charge command reads with no argument, and turns the limit on or off with one', () => {
  const read = chargeCommand();
  assert.deepEqual(read.slice(0, 2), ['sh', '-c']);
  assert.equal(read[3], 'sh');
  assert.equal(read[4], '');
  assert.equal(chargeCommand(true)[4], 'true');
  assert.equal(chargeCommand(false)[4], 'false');
  assert.match(read[2], /EnableChargeThreshold b "\$1"/);
  assert.match(read[2], /get-property org\.freedesktop\.UPower "\$dev" org\.freedesktop\.UPower\.Device ChargeThresholdSupported ChargeThresholdEnabled ChargeEndThreshold/);
});

test('the charge command finds the battery from its threshold file and names it as UPower does', () => {
  const root = mkdtempSync(join(tmpdir(), 'charge-'));
  const stubs = join(root, 'stubs');
  mkdirSync(stubs);
  writeFileSync(join(stubs, 'busctl'), `#!/bin/sh\necho "$*" >> ${join(root, 'log')}\n[ "$2" = get-property ] && printf 'b true\\nb true\\nu 80\\n'\nexit 0\n`);
  chmodSync(join(stubs, 'busctl'), 0o755);
  const supply = join(root, 'macsmc-battery');
  mkdirSync(supply);
  writeFileSync(join(supply, 'charge_control_end_threshold'), '80\n');
  const [cmd, flag, script, name, arg] = chargeCommand(false);
  const r = spawnSync(cmd, [flag, script.replaceAll('/sys/class/power_supply', root), name, arg], { encoding: 'utf8', env: { PATH: stubs + ':' + process.env.PATH } });
  assert.equal(r.status, 0, r.stderr);
  assert.equal(chargeLimit(r.stdout), 80);
  const log = readFileSync(join(root, 'log'), 'utf8').trim().split('\n');
  assert.equal(log[0], '--system call org.freedesktop.UPower /org/freedesktop/UPower/devices/battery_macsmc_battery org.freedesktop.UPower.Device EnableChargeThreshold b false');
  assert.match(log[1], /^--system get-property org\.freedesktop\.UPower \/org\/freedesktop\/UPower\/devices\/battery_macsmc_battery /);
});

test('with no threshold file the charge command prints nothing and runs no busctl', () => {
  const root = mkdtempSync(join(tmpdir(), 'charge-'));
  const [cmd, flag, script, name, arg] = chargeCommand(true);
  const r = spawnSync(cmd, [flag, script.replaceAll('/sys/class/power_supply', root), name, arg], { encoding: 'utf8', env: { PATH: '/nonexistent:/usr/bin:/bin' } });
  assert.equal(r.status, 0, r.stderr);
  assert.equal(r.stdout, '');
});
