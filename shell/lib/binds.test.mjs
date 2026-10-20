import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

// niri matches the key itself; this checks that Mod+Space runs the launcher's toggle.
const binds = readFileSync(new URL('../../home/dot_config/niri/binds.kdl', import.meta.url), 'utf8');

test('Mod+Space has a title and spawns dots-call launcher toggle', () => {
  assert.match(binds, /^\s*Mod\+Space hotkey-overlay-title="[^"]+" \{ spawn "dots-call" "launcher" "toggle"; \}$/m);
});

test('Mod+Shift+T has a title and spawns dots-call themes toggle', () => {
  assert.match(binds, /^\s*Mod\+Shift\+T hotkey-overlay-title="[^"]+" \{ spawn "dots-call" "themes" "toggle"; \}$/m);
});

const esc = (s) => s.replace(/[+.]/g, '\\$&');
const spawns = (key, args) =>
  new RegExp(`^\\s*${esc(key)} [^{]*hotkey-overlay-title="[^"]+" \\{ spawn ${args.map((a) => `"${esc(a)}"`).join(' ')}; \\}$`, 'm');

test('Mod+A, Mod+I and Mod+/ toggle the notifications, focus the island and toggle the cheat sheet', () => {
  assert.match(binds, spawns('Mod+A', ['dots-call', 'notifs', 'toggle']));
  assert.match(binds, spawns('Mod+I', ['dots-call', 'island', 'focus']));
  assert.match(binds, spawns('Mod+Slash', ['dots-call', 'cheatsheet', 'toggle']));
});

test('workspace up and down keep a bind now that Mod+I is the island', () => {
  assert.match(binds, /^\s*Mod\+Page_Up hotkey-overlay-title="[^"]+" \{ focus-workspace-up; \}$/m);
  assert.match(binds, /^\s*Mod\+Page_Down hotkey-overlay-title="[^"]+" \{ focus-workspace-down; \}$/m);
  assert.doesNotMatch(binds, /^\s*Mod\+I [^{]*\{ focus-workspace-up; \}$/m);
});

test('the volume keys unmute the default sink and step it by 5 %, and the brightness keys go through the shell', () => {
  assert.match(binds, spawns('XF86AudioRaiseVolume', ['sh', '-c', 'wpctl set-mute @DEFAULT_AUDIO_SINK@ 0 && wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+']));
  assert.match(binds, spawns('XF86AudioLowerVolume', ['sh', '-c', 'wpctl set-mute @DEFAULT_AUDIO_SINK@ 0 && wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-']));
  assert.match(binds, spawns('XF86AudioMute', ['wpctl', 'set-mute', '@DEFAULT_AUDIO_SINK@', 'toggle']));
  assert.match(binds, spawns('XF86AudioMicMute', ['wpctl', 'set-mute', '@DEFAULT_AUDIO_SOURCE@', 'toggle']));
  assert.match(binds, spawns('XF86MonBrightnessUp', ['dots-call', 'osd', 'brightness', '5%+']));
  assert.match(binds, spawns('XF86MonBrightnessDown', ['dots-call', 'osd', 'brightness', '5%-']));
});

// Apple keyboards send these on F7 to F9, and nothing answered them.
test('the media keys play, pause and skip through the shell', () => {
  assert.match(binds, spawns('XF86AudioPlay', ['dots-call', 'media', 'playPause']));
  assert.match(binds, spawns('XF86AudioNext', ['dots-call', 'media', 'next']));
  assert.match(binds, spawns('XF86AudioPrev', ['dots-call', 'media', 'previous']));
});

test('the system binds open Control, the clipboard and emoji modes, the lock and the recorder', () => {
  assert.match(binds, spawns('Mod+C', ['dots-call', 'control', 'toggle']));
  assert.match(binds, spawns('Mod+V', ['dots-call', 'launcher', 'mode', 'clipboard']));
  assert.match(binds, spawns('Mod+Period', ['dots-call', 'launcher', 'mode', 'emoji']));
  assert.match(binds, spawns('Mod+Escape', ['dots-call', 'lock', 'lock']));
  assert.match(binds, spawns('Mod+Shift+R', ['dots-call', 'record', 'toggle']));
});

test('Mod+G toggles Goals', () => {
  assert.match(binds, spawns('Mod+G', ['dots-call', 'goals', 'toggle']));
});

test('Print opens niri screenshot UI and center-column moves to Mod+Shift+C', () => {
  assert.match(binds, /^\s*Print hotkey-overlay-title="[^"]+" \{ screenshot; \}$/m);
  assert.match(binds, /^\s*Mod\+Shift\+C hotkey-overlay-title="[^"]+" \{ center-column; \}$/m);
});

test('niri shows no hotkey overlay at login, so the artboard is the first thing on screen', () => {
  const config = readFileSync(new URL('../../home/dot_config/niri/config.kdl', import.meta.url), 'utf8');
  assert.match(config, /^hotkey-overlay \{\n\s+skip-at-startup\n\}$/m);
});
