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

const esc = (s) => s.replace(/[+.]/g, '\\$&');
const spawns = (key, args) =>
  new RegExp(`^\\s*${esc(key)} [^{]*hotkey-overlay-title="[^"]+" \\{ spawn ${args.map((a) => `"${esc(a)}"`).join(' ')}; \\}$`, 'm');

test('Mod+A, Mod+I and Mod+/ toggle the notifications, focus the island and toggle the cheat sheet', () => {
  assert.match(binds, spawns('Mod+A', ['qs', 'ipc', 'call', 'notifs', 'toggle']));
  assert.match(binds, spawns('Mod+I', ['qs', 'ipc', 'call', 'island', 'focus']));
  assert.match(binds, spawns('Mod+Slash', ['qs', 'ipc', 'call', 'cheatsheet', 'toggle']));
});

test('workspace up and down keep a bind now that Mod+I is the island', () => {
  assert.match(binds, /^\s*Mod\+Page_Up hotkey-overlay-title="[^"]+" \{ focus-workspace-up; \}$/m);
  assert.match(binds, /^\s*Mod\+Page_Down hotkey-overlay-title="[^"]+" \{ focus-workspace-down; \}$/m);
  assert.doesNotMatch(binds, /^\s*Mod\+I [^{]*\{ focus-workspace-up; \}$/m);
});

test('the volume keys step the default sink by 5 % and the brightness keys go through the shell', () => {
  assert.match(binds, spawns('XF86AudioRaiseVolume', ['wpctl', 'set-volume', '-l', '1', '@DEFAULT_AUDIO_SINK@', '5%+']));
  assert.match(binds, spawns('XF86AudioLowerVolume', ['wpctl', 'set-volume', '@DEFAULT_AUDIO_SINK@', '5%-']));
  assert.match(binds, spawns('XF86AudioMute', ['wpctl', 'set-mute', '@DEFAULT_AUDIO_SINK@', 'toggle']));
  assert.match(binds, spawns('XF86MonBrightnessUp', ['qs', 'ipc', 'call', 'osd', 'brightness', '5%+']));
  assert.match(binds, spawns('XF86MonBrightnessDown', ['qs', 'ipc', 'call', 'osd', 'brightness', '5%-']));
});

test('m5 binds open Control, the clipboard and emoji modes, the lock and the recorder', () => {
  assert.match(binds, spawns('Mod+C', ['qs', 'ipc', 'call', 'control', 'toggle']));
  assert.match(binds, spawns('Mod+V', ['qs', 'ipc', 'call', 'launcher', 'mode', 'clipboard']));
  assert.match(binds, spawns('Mod+Period', ['qs', 'ipc', 'call', 'launcher', 'mode', 'emoji']));
  assert.match(binds, spawns('Mod+Escape', ['qs', 'ipc', 'call', 'lock', 'lock']));
  assert.match(binds, spawns('Mod+Shift+R', ['qs', 'ipc', 'call', 'record', 'toggle']));
});

test('Print opens niri screenshot UI and center-column moves to Mod+Shift+C', () => {
  assert.match(binds, /^\s*Print hotkey-overlay-title="[^"]+" \{ screenshot; \}$/m);
  assert.match(binds, /^\s*Mod\+Shift\+C hotkey-overlay-title="[^"]+" \{ center-column; \}$/m);
});
