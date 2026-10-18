import { test } from 'node:test';
import assert from 'node:assert/strict';
import { backlights, ddcDisplays, routeOf, ACTIONS, actionCommand } from './control-system.mjs';

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
