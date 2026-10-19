import { test } from 'node:test';
import assert from 'node:assert/strict';
import { backlights, ddcDisplays, routeOf, ACTIONS, actionCommand, parseSync, syncFailing, syncRows } from './control-system.mjs';

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
