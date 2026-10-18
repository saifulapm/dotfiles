import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

// niri matches the key itself; this checks that Mod+Space runs the launcher's toggle.
const binds = readFileSync(new URL('../../home/dot_config/niri/binds.kdl', import.meta.url), 'utf8');

test('Mod+Space has a title and spawns qs ipc call launcher toggle', () => {
  assert.match(binds, /^\s*Mod\+Space hotkey-overlay-title="[^"]+" \{ spawn "qs" "ipc" "call" "launcher" "toggle"; \}$/m);
});

test('Mod+Shift+T has a title and spawns qs ipc call themes toggle', () => {
  assert.match(binds, /^\s*Mod\+Shift\+T hotkey-overlay-title="[^"]+" \{ spawn "qs" "ipc" "call" "themes" "toggle"; \}$/m);
});
