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

test('the keymap opens Chromium on Mod+B, kak on Mod+E, yazi on Mod+Y and the overview on Mod+O', () => {
  assert.match(binds, spawns('Mod+B', ['chromium-browser']));
  assert.match(binds, spawns('Mod+E', ['dots-foot', 'kak']));
  assert.match(binds, spawns('Mod+Y', ['dots-foot', 'yazi']));
  assert.doesNotMatch(binds, /^\s*Mod\+Shift\+E /m);
  assert.match(binds, /^\s*Mod\+O repeat=false hotkey-overlay-title="[^"]+" \{ toggle-overview; \}$/m);
});

const acts = (key, action) => new RegExp(`^\\s*${esc(key)} [^{]*\\{ ${action.replace(/[+.()"]/g, '\\$&')}; \\}$`, 'm');

test('Mod+D toggles Do Not Disturb, Mod+Shift+A clears the notifications and Mod+Shift+Escape opens btop', () => {
  assert.match(binds, spawns('Mod+D', ['dots-call', 'notifs', 'toggleDnd']));
  assert.match(binds, spawns('Mod+Shift+A', ['dots-call', 'notifs', 'clear']));
  assert.match(binds, spawns('Mod+Shift+Escape', ['dots-foot', 'btop']));
});

test('J and K cross into the next workspace at the edge, and U is no longer bound', () => {
  assert.match(binds, acts('Mod+J', 'focus-window-or-workspace-down'));
  assert.match(binds, acts('Mod+K', 'focus-window-or-workspace-up'));
  assert.match(binds, acts('Mod+Ctrl+J', 'move-window-down-or-to-workspace-down'));
  assert.match(binds, acts('Mod+Ctrl+K', 'move-window-up-or-to-workspace-up'));
  assert.doesNotMatch(binds, /^\s*Mod\+(Ctrl\+)?U /m);
  assert.doesNotMatch(binds, /^\s*Mod\+Ctrl\+I /m);
});

test('arrows, Home and End mirror h/j/k/l, and 0, Ctrl+Tab and the wheel reach workspaces', () => {
  for (const [k, a] of [['Left', 'focus-column-left'], ['Right', 'focus-column-right'], ['Down', 'focus-window-or-workspace-down'], ['Up', 'focus-window-or-workspace-up']]) {
    assert.match(binds, acts(`Mod+${k}`, a));
  }
  assert.match(binds, acts('Mod+Ctrl+Left', 'move-column-left'));
  assert.match(binds, acts('Mod+Home', 'focus-column-first'));
  assert.match(binds, acts('Mod+End', 'focus-column-last'));
  assert.match(binds, acts('Mod+0', 'focus-workspace 10'));
  assert.match(binds, acts('Mod+Ctrl+0', 'move-column-to-workspace 10'));
  assert.match(binds, acts('Mod+Ctrl+Tab', 'focus-workspace-previous'));
  assert.match(binds, acts('Mod+WheelScrollDown', 'focus-workspace-down'));
  assert.match(binds, acts('Mod+Shift+WheelScrollDown', 'focus-column-right'));
});

test('the sizing and column binds follow niri', () => {
  for (const [k, a] of [
    ['Mod+R', 'switch-preset-column-width'], ['Mod+Minus', 'set-column-width "-10%"'], ['Mod+Equal', 'set-column-width "+10%"'],
    ['Mod+Shift+Minus', 'set-window-height "-10%"'], ['Mod+Shift+Equal', 'set-window-height "+10%"'], ['Mod+Ctrl+R', 'reset-window-height'],
    ['Mod+Ctrl+F', 'expand-column-to-available-width'], ['Mod+M', 'maximize-window-to-edges'], ['Mod+W', 'toggle-column-tabbed-display'],
    ['Mod+BracketLeft', 'consume-or-expel-window-left'], ['Mod+BracketRight', 'consume-or-expel-window-right'], ['Mod+Comma', 'consume-window-into-column'],
    ['Mod+Ctrl+V', 'toggle-window-floating'], ['Mod+Shift+V', 'switch-focus-between-floating-and-tiling'], ['Mod+Ctrl+C', 'center-visible-columns'],
  ]) assert.match(binds, acts(k, a));
});

test('Mod+Shift+3, 4 and 5 take the screen, a region and the window, and 8, 9 and 0 set the cast target', () => {
  assert.match(binds, acts('Mod+Shift+3', 'screenshot-screen'));
  assert.match(binds, acts('Mod+Shift+4', 'screenshot'));
  assert.match(binds, acts('Mod+Shift+5', 'screenshot-window'));
  assert.match(binds, acts('Mod+Shift+8', 'set-dynamic-cast-window'));
  assert.match(binds, acts('Mod+Shift+9', 'set-dynamic-cast-monitor'));
  assert.match(binds, acts('Mod+Shift+0', 'clear-dynamic-cast-target'));
});

test('the Touch Bar keys light the keyboard and search, and Alt and Shift fine-tune volume and brightness', () => {
  assert.match(binds, spawns('XF86KbdBrightnessUp', ['brightnessctl', '-q', '-d', 'kbd_backlight', 'set', '10%+']));
  assert.match(binds, spawns('XF86KbdBrightnessDown', ['brightnessctl', '-q', '-d', 'kbd_backlight', 'set', '10%-']));
  assert.match(binds, spawns('XF86Search', ['dots-call', 'launcher', 'toggle']));
  assert.match(binds, spawns('XF86AudioPause', ['dots-call', 'media', 'playPause']));
  assert.match(binds, spawns('Alt+XF86AudioRaiseVolume', ['sh', '-c', 'wpctl set-mute @DEFAULT_AUDIO_SINK@ 0 && wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 1%+']));
  assert.match(binds, spawns('Alt+XF86AudioLowerVolume', ['sh', '-c', 'wpctl set-mute @DEFAULT_AUDIO_SINK@ 0 && wpctl set-volume @DEFAULT_AUDIO_SINK@ 1%-']));
  assert.match(binds, spawns('Alt+XF86MonBrightnessUp', ['dots-call', 'osd', 'brightness', '1%+']));
  assert.match(binds, spawns('Alt+XF86MonBrightnessDown', ['dots-call', 'osd', 'brightness', '1%-']));
  assert.match(binds, spawns('Shift+XF86MonBrightnessUp', ['dots-call', 'osd', 'brightness', '100%']));
  assert.match(binds, spawns('Shift+XF86MonBrightnessDown', ['dots-call', 'osd', 'brightness', '1%']));
  assert.match(binds, acts('Mod+Shift+P', 'power-off-monitors'));
});

test('picture-in-picture, viewers and Chromium sign-in and sharing windows float, and terminals scroll faster', () => {
  const rules = readFileSync(new URL('../../home/dot_config/niri/rules.kdl', import.meta.url), 'utf8');
  const block = (re) => rules.split(/^window-rule /m).find((r) => re.test(r)) ?? '';
  assert.match(block(/Picture/), /open-floating true/);
  assert.match(block(/\^mpv\$/), /open-floating true/);
  assert.match(block(/sign in/), /open-floating true/);
  assert.match(block(/title=r#"\(\?i\)is sharing/), /open-focused false/);
  assert.match(block(/footclient/), /scroll-factor 1\.5/);
});

// niri suspends on the power key before any bind unless its handling is off, and Asahi's resume can leave the display dead.
test('the power key opens Control on Power instead of suspending', () => {
  const config = readFileSync(new URL('../../home/dot_config/niri/config.kdl', import.meta.url), 'utf8');
  assert.match(config, /^input \{[^]*?^\s+disable-power-key-handling$[^]*?^\}$/m);
  assert.match(binds, spawns('XF86PowerOff', ['dots-call', 'control', 'section', 'power']));
});

test('niri shows no hotkey overlay at login, so the artboard is the first thing on screen', () => {
  const config = readFileSync(new URL('../../home/dot_config/niri/config.kdl', import.meta.url), 'utf8');
  assert.match(config, /^hotkey-overlay \{\n\s+skip-at-startup\n\}$/m);
});
