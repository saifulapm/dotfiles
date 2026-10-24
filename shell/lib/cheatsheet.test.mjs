import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { parseBinds, groupRows, columnsOf, filterRows, TOUCHPAD } from './cheatsheet.mjs';

const binds = readFileSync(new URL('../../home/dot_config/niri/binds.kdl', import.meta.url), 'utf8');
const row = (line) => parseBinds(line)[0];

test('the repo binds give one row per titled bind, each with a title, key and group', () => {
  const titled = binds.match(/hotkey-overlay-title=/g).length;
  const rows = parseBinds(binds);
  assert.equal(rows.length, titled);
  for (const r of rows) {
    assert.ok(r.title && r.key, JSON.stringify(r));
    assert.ok(['SURFACES', 'WORK', 'WINDOWS', 'SYSTEM'].includes(r.group), JSON.stringify(r));
  }
});

test('the switcher keys and the column and shortcut-inhibit binds are rows', () => {
  const keys = (title) => parseBinds(binds).filter((r) => r.title === title).map((r) => r.key);
  assert.deepEqual(keys('Switch Windows'), ['⌥ Tab', 'Mod Tab']);
  assert.deepEqual(keys('Switch Windows Back'), ['⌥ ⇧ Tab', 'Mod ⇧ Tab']);
  assert.deepEqual(keys('Expel Window from Column'), ['Mod ⇧ ,']);
  assert.deepEqual(keys('Toggle Shortcut Inhibit'), ['Mod ⌃ Esc']);
});

test('a bind without a title gives no row', () => {
  assert.deepEqual(parseBinds('    Mod+Z { spawn "foot"; }\n'), []);
});

test('keys read the designs way', () => {
  assert.equal(row('    Mod+Space hotkey-overlay-title="Launcher" { spawn "qs" "ipc" "call" "launcher" "toggle"; }').key, 'Mod Space');
  assert.equal(row('    Mod+Shift+T hotkey-overlay-title="Themes" { spawn "qs" "ipc" "call" "themes" "toggle"; }').key, 'Mod ⇧ T');
  assert.equal(row('    Mod+Ctrl+H hotkey-overlay-title="Move Column Left" { move-column-left; }').key, 'Mod ⌃ H');
  assert.equal(row('    Mod+Slash hotkey-overlay-title="Cheat Sheet" { spawn "qs" "ipc" "call" "cheatsheet" "toggle"; }').key, 'Mod /');
  assert.equal(row('    Mod+Return hotkey-overlay-title="Open a Terminal: foot" { spawn "foot"; }').key, 'Mod ↵');
  assert.equal(row('    Mod+Page_Up hotkey-overlay-title="Focus Workspace Up" { focus-workspace-up; }').key, 'Mod PgUp');
  assert.equal(row('    Mod+Page_Down hotkey-overlay-title="Focus Workspace Down" { focus-workspace-down; }').key, 'Mod PgDn');
  assert.equal(row('    XF86AudioRaiseVolume allow-when-locked=true hotkey-overlay-title="Volume Up" { spawn "wpctl" "set-volume" "-l" "1" "@DEFAULT_AUDIO_SINK@" "5%+"; }').key, 'Volume Up');
});

test('a title comes through after other properties', () => {
  assert.deepEqual(row('    Mod+Q repeat=false hotkey-overlay-title="Close Window" { close-window; }'), { title: 'Close Window', key: 'Mod Q', group: 'WINDOWS' });
});

test('binds group into surfaces, work, windows and system', () => {
  assert.equal(row('    Mod+Slash hotkey-overlay-title="Cheat Sheet" { spawn "qs" "ipc" "call" "cheatsheet" "toggle"; }').group, 'SURFACES');
  assert.equal(row('    Mod+I hotkey-overlay-title="Island" { spawn "qs" "ipc" "call" "island" "focus"; }').group, 'SURFACES');
  assert.equal(row('    Mod+Return hotkey-overlay-title="Open a Terminal: foot" { spawn "foot"; }').group, 'WORK');
  assert.equal(row('    Mod+1 hotkey-overlay-title="Focus Workspace 1" { focus-workspace 1; }').group, 'WINDOWS');
  assert.equal(row('    Mod+F hotkey-overlay-title="Maximize Column" { maximize-column; }').group, 'WINDOWS');
  assert.equal(row('    Mod+Shift+Q hotkey-overlay-title="Quit niri" { quit; }').group, 'SYSTEM');
  assert.equal(row('    Print hotkey-overlay-title="Screenshot" { screenshot; }').group, 'SYSTEM');
  // The media keys spawn qs and wpctl, yet they are system keys, not surfaces or apps.
  assert.equal(row('    XF86MonBrightnessUp allow-when-locked=true hotkey-overlay-title="Brightness Up" { spawn "qs" "ipc" "call" "osd" "brightness" "5%+"; }').group, 'SYSTEM');
  assert.equal(row('    XF86AudioMute allow-when-locked=true hotkey-overlay-title="Mute" { spawn "wpctl" "set-mute" "@DEFAULT_AUDIO_SINK@" "toggle"; }').group, 'SYSTEM');
});

test('rows group into the five groups in order, empty ones kept', () => {
  const rows = parseBinds('    Mod+Shift+Q hotkey-overlay-title="Quit niri" { quit; }\n    Mod+Space hotkey-overlay-title="Launcher" { spawn "qs" "ipc" "call" "launcher" "toggle"; }\n');
  assert.deepEqual(
    groupRows(rows).map((g) => [g.name, g.rows.map((r) => r.title)]),
    [['SURFACES', ['Launcher']], ['WORK', []], ['WINDOWS', []], ['SYSTEM', ['Quit niri']], ['TOUCHPAD', []]],
  );
});

// Four columns as before, so no column narrows: the short SYSTEM one also holds the touchpad.
test('the five groups lay out in four columns, TOUCHPAD under SYSTEM', () => {
  assert.deepEqual(columnsOf(groupRows([])).map((col) => col.map((g) => g.name)), [['SURFACES'], ['WORK'], ['WINDOWS'], ['SYSTEM', 'TOUCHPAD']]);
});

// binds.kdl cannot hold these: niri's own swipes and corner, and dots-gestures' pinches and the margins' corner.
test('the touchpad rows name niri\'s swipes and corner, the two pinches and the Notes corner', () => {
  assert.deepEqual(TOUCHPAD.map((r) => [r.key, r.title, r.group]), [
    ['3-finger ↕', 'Switch Workspace', 'TOUCHPAD'],
    ['3-finger ↔', 'Scroll Columns', 'TOUCHPAD'],
    ['4-finger ↕', 'Overview', 'TOUCHPAD'],
    ['4-finger pinch', 'Launcher', 'TOUCHPAD'],
    ['4-finger spread', 'Overview', 'TOUCHPAD'],
    ['↙ corner', 'Overview', 'TOUCHPAD'],
    ['↗ corner', 'Notes', 'TOUCHPAD'],
  ]);
  assert.deepEqual(filterRows(TOUCHPAD, 'pinch').map((r) => r.title), ['Launcher']);
});

test('a filter matches the title or the key text, ignoring case', () => {
  const rows = parseBinds(binds);
  assert.deepEqual(filterRows(rows, 'theme').map((r) => r.title), ['Themes']);
  assert.deepEqual(filterRows(rows, 'mod ⇧').map((r) => r.title), [
    'Mail: kak-mail', 'Themes', 'Clear Notifications', 'Pin Notes', 'DNS Shield', 'System Monitor: btop', 'Quit niri', 'Screens Off', 'Screenshot: Screen', 'Screenshot: Region',
    'Screenshot: Window', 'Copy Text from a Region', 'Annotate a Region', 'Record a Region', 'Cast: Focused Window', 'Cast: Focused Screen', 'Cast: Nothing', 'Window Shorter', 'Window Taller',
    'Fullscreen Window', 'Expel Window from Column', 'Focus Floating or Tiled', 'Center Column', 'Move Workspace Down', 'Move Workspace Up',
    'Switch Windows Back',
  ]);
  assert.equal(filterRows(rows, '').length, rows.length);
});
