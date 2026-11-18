import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { parseBinds, groupRows, columnsOf, filterRows, TOUCHPAD, GROUPS_SIX, IN_SURFACES, groupRowsSix, columnsOfSix, chipsOf } from './cheatsheet.mjs';

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
  assert.equal(row('    Mod+Semicolon hotkey-overlay-title="Click a Target" { spawn "wl-kbptr"; }').key, 'Mod ;');
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
  // nirius moves windows, so its binds are window binds though they spawn.
  assert.equal(row('    Mod+Shift+Z hotkey-overlay-title="Window to Scratchpad or Back" { spawn "nirius" "scratchpad-toggle"; }').group, 'WINDOWS');
  assert.equal(row('    Mod+Z hotkey-overlay-title="Show Scratchpad" { spawn "dots-scratchpad"; }').group, 'WINDOWS');
  assert.equal(row('    Mod+Shift+Q hotkey-overlay-title="Quit niri" { quit; }').group, 'SYSTEM');
  assert.equal(row('    Print hotkey-overlay-title="Screenshot" { screenshot; }').group, 'SYSTEM');
  // The media keys spawn qs and wpctl, yet they are system keys, not surfaces or apps.
  assert.equal(row('    XF86MonBrightnessUp allow-when-locked=true hotkey-overlay-title="Brightness Up" { spawn "qs" "ipc" "call" "osd" "brightness" "5%+"; }').group, 'SYSTEM');
  assert.equal(row('    XF86AudioMute allow-when-locked=true hotkey-overlay-title="Mute" { spawn "wpctl" "set-mute" "@DEFAULT_AUDIO_SINK@" "toggle"; }').group, 'SYSTEM');
});

// The binds reach the shell through dots-call now, and a surface is still a surface.
test('the shell\'s surfaces group as SURFACES, not WORK', () => {
  assert.equal(row('    Mod+N hotkey-overlay-title="Notes" { spawn "dots-call" "notes" "toggle"; }').group, 'SURFACES');
  const rows = parseBinds(binds);
  const titles = (g) => rows.filter((r) => r.group === g).map((r) => r.title);
  for (const t of ['Launcher', 'Notes', 'Control', 'Pass']) assert.ok(titles('SURFACES').includes(t), t);
  assert.deepEqual(titles('WORK').filter((t) => titles('SURFACES').includes(t)), []);
});

// A media key under a modifier reads as that key's own row does, behind the modifier, and stays a system key.
test('a media key with a modifier shows the modifier and the bare key\'s name', () => {
  const rows = parseBinds(binds);
  const of = (title) => rows.find((r) => r.title === title);
  assert.deepEqual([of('Volume Up 1%').key, of('Volume Up 1%').group], ['⌥ Volume Up', 'SYSTEM']);
  assert.deepEqual([of('Brightness Full').key, of('Brightness Full').group], ['⇧ Brightness Up', 'SYSTEM']);
  assert.deepEqual([of('Brightness Down 1%').key, of('Brightness Down 1%').group], ['⌥ Brightness Down', 'SYSTEM']);
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
  assert.deepEqual(filterRows(rows, 'colorsch').map((r) => r.title), ['Colorschemes']);
  assert.deepEqual(filterRows(rows, 'mod ⇧').map((r) => r.title), [
    'Mail: kak-mail', 'Click by Grid', 'Colorschemes', 'Clear Notifications', 'Pin Notes', 'DNS Shield', 'System Monitor: btop', 'Quit niri', 'Screens Off', 'Screenshot: Screen', 'Screenshot: Region',
    'Screenshot: Window', 'Copy Text from a Region', 'Annotate a Region', 'Record a Region', 'Cast: Focused Window', 'Cast: Focused Screen', 'Cast: Nothing', 'Window Shorter', 'Window Taller',
    'Fullscreen Window', 'Expel Window from Column', 'Focus Floating or Tiled', 'Center Column',
    'Window to Scratchpad or Back', 'Window Follows Workspaces', 'Move Workspace Down', 'Move Workspace Up',
    'Switch Windows Back',
  ]);
  assert.equal(filterRows(rows, '').length, rows.length);
});

const SURFACES = ['launcher', 'control', 'notifications', 'pass', 'tailscale', 'accounts', 'dns', 'goals'];

test('the six groups are the surfaces, the keys inside them, work, windows, system and the touchpad', () => {
  assert.deepEqual(GROUPS_SIX, ['SURFACES', 'IN SURFACES', 'WORK', 'WINDOWS', 'SYSTEM', 'TOUCHPAD']);
});

test('IN SURFACES lists the shared keys, Esc among them, then each surface\'s own in order', () => {
  assert.ok(IN_SURFACES.some((r) => r.surface === 'shared' && r.key === 'Esc'));
  const order = [];
  for (const r of IN_SURFACES) if (order[order.length - 1] !== r.surface) order.push(r.surface);
  assert.deepEqual(order, ['shared'].concat(SURFACES));
  for (const r of IN_SURFACES) assert.ok(r.title && r.group === 'IN SURFACES', JSON.stringify(r));
});

test('the real binds, the surface keys and the touchpad fill six groups in six columns', () => {
  const groups = groupRowsSix(parseBinds(binds).concat(IN_SURFACES, TOUCHPAD));
  assert.deepEqual(groups.map((g) => g.name), ['SURFACES', 'IN SURFACES', 'WORK', 'WINDOWS', 'SYSTEM', 'TOUCHPAD']);
  for (const g of groups) assert.ok(g.rows.length > 0, g.name);
  assert.deepEqual(groups[1].rows.filter((r) => !r.caption), IN_SURFACES);
  assert.deepEqual(columnsOfSix(groups).map((col) => col.map((g) => g.name)), [['SURFACES'], ['IN SURFACES'], ['WORK'], ['WINDOWS'], ['SYSTEM'], ['TOUCHPAD']]);
});

// What a row's key text must find in its surface's code, every pattern of it; a key text missing here fails the test.
const CODE = {
  Esc: [/Key_Escape\b/],
  'J / K': [/Key_J\b/, /Key_K\b/],
  '↑ / ↓': [/Key_Up\b/, /Key_Down\b/],
  'H / L': [/Key_H\b/, /Key_L\b/],
  'H J K L': [/Key_H\b/, /Key_J\b/, /Key_K\b/, /Key_L\b/],
  '- / =': [/Key_Minus\b/, /Key_Equal\b/],
  '- / +': [/Key_Minus\b/, /Key_Plus\b/],
  '⇧ J / K': [/ShiftModifier/, /Key_J\b/, /Key_K\b/],
  '↵': [/Key_Return\b/],
  '⇧ ↵': [/ShiftModifier/, /Key_Return\b/],
  Tab: [/Key_Tab\b/],
  '⇧ Tab': [/ShiftModifier/, /Key_Tab\b/],
  Space: [/Key_Space\b/],
  '/': [/Key_Slash\b/],
  '1-9': [/\[1-9\]/],
  '1-5': [/Key_1\b/, /Key_5\b/],
  '⇧ D': [/ShiftModifier/, /Key_D\b/],
  '⇧ O': [/Key_O\b/, /"O"/],
  'w␣': [/'w '/],
  'v␣': [/'v '/],
  ':␣': [/': '/],
  '=␣': [/'= '/],
  '>␣': [/'> '/],
  'r␣': [/'r '/],
  'c␣': [/'c '/],
};
const pattern = (key) => CODE[key] || (/^[A-Z]$/.test(key) ? [new RegExp(`Key_${key}\\b`)] : null);

const shell = new URL('../', import.meta.url);
const read = (name) => readFileSync(new URL(name, shell), 'utf8');
const control = readdirSync(shell).filter((f) => /^Control.*\.qml$/.test(f));
const FILES = {
  launcher: ['Launcher.qml', 'lib/launcher.mjs'],
  control,
  notifications: ['Notifications.qml'],
  pass: ['Pass.qml'],
  tailscale: ['Tailscale.qml'],
  accounts: ['Accounts.qml'],
  dns: ['Dns.qml'],
  goals: ['Goals.qml'],
};

// The sheet is the only place a surface's keys show, so each row must name a key its surface's code handles.
test('every IN SURFACES row names a key its surface\'s code handles, a shared row every surface\'s', () => {
  assert.ok(control.includes('Control.qml') && control.length > 1, control.join());
  for (const r of IN_SURFACES) {
    const want = pattern(r.key);
    assert.ok(want, `no code pattern for ${r.key}`);
    for (const s of r.surface === 'shared' ? SURFACES : [r.surface]) {
      const code = FILES[s].map(read).join('\n');
      for (const p of want) assert.ok(p.test(code), `${s} ${r.key} ${r.title}: no ${p}`);
    }
  }
});

test('IN SURFACES lists the notification centre\'s rules keys', () => {
  const keys = IN_SURFACES.filter((r) => r.surface === 'notifications').map((r) => r.key);
  assert.deepEqual(keys, ['↵', 'D', '⇧ D', 'M', 'I', 'S', 'H / L', '/', '1-9']);
});

test('IN SURFACES lists every key Pass takes on its list and in a new entry', () => {
  const keys = IN_SURFACES.filter((r) => r.surface === 'pass').map((r) => r.key);
  assert.deepEqual(keys, ['Tab', '↵', 'O', 'S', 'N', '- / +', 'E', 'D', 'Q', '/']);
});

// No surface shows key hints (8HYAV3GE): the five tools in the island draw no legend, so the sheet is where their keys are.
test('none of the island\'s tools draws a key strip or a key hint', () => {
  const tools = { pass: ['Pass.qml', 'lib/pass.mjs'], tailscale: ['Tailscale.qml', 'lib/tailscale.mjs'], accounts: ['Accounts.qml', 'lib/accounts.mjs'], dns: ['Dns.qml', 'lib/dns.mjs'], goals: ['Goals.qml', 'lib/goals-view.mjs'] };
  for (const [name, files] of Object.entries(tools)) {
    const code = files.map(read).join('\n');
    for (const hint of [/\bKeyPair\b/, /\.keys\(\[/, /\bkeyText\(/, /\bhint:/]) assert.doesNotMatch(code, hint, `${name} draws a key hint: ${hint}`);
  }
});

test('IN SURFACES lists Control\'s - and = under Control', () => {
  const keys = IN_SURFACES.filter((r) => r.surface === 'control').map((r) => r.key);
  assert.ok(keys.includes('- / ='), keys.join());
  assert.deepEqual(chipsOf('- / ='), ['-', '=']);
});

test('a row key draws as one chip per key, with the / between a pair dropped', () => {
  assert.deepEqual(chipsOf('Mod ⇧ T'), ['Mod', '⇧', 'T']);
  assert.deepEqual(chipsOf('J / K'), ['J', 'K']);
  assert.deepEqual(chipsOf('Esc'), ['Esc']);
  assert.deepEqual(chipsOf('1-9'), ['1-9']);
  assert.deepEqual(chipsOf('/'), ['/']);
});

test('a / that is the key itself stays a key, as the cheat sheet\'s own Mod / does', () => {
  assert.deepEqual(chipsOf('Mod /'), ['Mod', '/']);
  assert.deepEqual(chipsOf('Mod ⇧ /'), ['Mod', '⇧', '/']);
  const own = parseBinds(readFileSync(new URL('../../home/dot_config/niri/binds.kdl', import.meta.url), 'utf8')).find((r) => r.title === 'Cheat Sheet' || /cheat/i.test(r.title));
  assert.deepEqual(chipsOf(own.key), ['Mod', '/']);
});

test('IN SURFACES names each surface in a caption row before its keys, the shared keys under Every Surface', () => {
  const group = groupRowsSix(IN_SURFACES).find((g) => g.name === 'IN SURFACES');
  const captions = group.rows.filter((r) => r.caption).map((r) => r.caption);
  assert.deepEqual(captions, ['Every Surface', 'Launcher', 'Control', 'Notifications', 'Pass', 'Tailscale', 'Accounts', 'DNS', 'Goals']);
  group.rows.forEach((r, i) => {
    if (r.caption) return;
    const above = group.rows.slice(0, i).reverse().find((x) => x.caption);
    assert.equal(above.surface, r.surface, `${r.title} sits under ${above.caption}`);
  });
});

test('a filtered IN SURFACES keeps only the captions of surfaces with a row left', () => {
  const group = groupRowsSix(filterRows(IN_SURFACES, 'kid')).find((g) => g.name === 'IN SURFACES');
  assert.deepEqual(group.rows.map((r) => r.caption ?? r.title), ['DNS', 'Kid Mode']);
});

test('minus, equal, [ and ] read as the keys they print', () => {
  const rows = parseBinds(['Mod+Minus hotkey-overlay-title="Column Narrower" { set-column-width "-10%"; }', 'Mod+Equal hotkey-overlay-title="Column Wider" { set-column-width "+10%"; }', 'Mod+BracketLeft hotkey-overlay-title="Pull In or Push Out Left" { consume-or-expel-window-left; }', 'Mod+BracketRight hotkey-overlay-title="Pull In or Push Out Right" { consume-or-expel-window-right; }'].join('\n'));
  assert.deepEqual(rows.map((r) => r.key), ['Mod -', 'Mod =', 'Mod [', 'Mod ]']);
});

// The launcher draws no legend, so the sheet is the only place its prefixes show.
test('IN SURFACES lists every launcher prefix', () => {
  const keys = IN_SURFACES.filter((r) => r.surface === 'launcher').map((r) => r.key);
  for (const k of ['w␣', 'v␣', ':␣', '=␣', '>␣', 'r␣', 'c␣']) assert.ok(keys.includes(k), `no launcher row for ${k}`);
});
