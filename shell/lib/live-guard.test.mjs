import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';

// dots theme reloads apps on whatever display and bus it inherits, and writes the agents' themes under DOTS_AGENT_HOME, so a unit test that runs it must cut all three.
const lib = new URL('.', import.meta.url).pathname;

test('every unit test that runs bin/dots empties WAYLAND_DISPLAY and points DBUS_SESSION_BUS_ADDRESS and DOTS_AGENT_HOME away', () => {
  const unguarded = readdirSync(lib)
    .filter((f) => f.endsWith('.test.mjs') && f !== 'live-guard.test.mjs')
    .filter((f) => {
      const text = readFileSync(join(lib, f), 'utf8');
      return /bin\/dots['`]/.test(text) && !(/WAYLAND_DISPLAY: ''/.test(text) && /DBUS_SESSION_BUS_ADDRESS: /.test(text) && /DOTS_AGENT_HOME: /.test(text));
    });
  assert.deepEqual(unguarded, []);
});
