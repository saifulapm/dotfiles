import { test } from 'node:test';
import assert from 'node:assert/strict';
import { rank, parseQuery, windowRows, commandRows, calcRows, convertRows, overviewChar, schemeRows, stampedExec, schemeList, scroll, wheel } from './launcher.mjs';
import { execFileSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const app = (name, keywords = []) => ({ id: name.toLowerCase(), name, genericName: '', keywords });
const names = (entries) => entries.map((e) => e.name);

test('foot ranks the entry named Foot first', () => {
  const entries = [app('Foot Server'), app('Footnote Editor'), app('Foot Client'), app('Foot'), app('Firefox')];
  assert.deepEqual(names(rank(entries, 'foot')), ['Foot', 'Foot Client', 'Foot Server', 'Footnote Editor']);
});

test('name prefix, then word prefix, then substring, then keywords', () => {
  const entries = [app('Image Editor', ['vips']), app('Davinci'), app('Font Viewer'), app('Vim'), app('Calculator')];
  assert.deepEqual(names(rank(entries, 'vi')), ['Vim', 'Font Viewer', 'Davinci', 'Image Editor']);
});

test('matching ignores case', () => {
  assert.deepEqual(names(rank([app('Font Viewer'), app('mpv')], 'FONT')), ['Font Viewer']);
});

test('an empty query lists every entry by name', () => {
  assert.deepEqual(names(rank([app('zathura'), app('Foot'), app('Chromium')], '')), ['Chromium', 'Foot', 'zathura']);
});

test('parseQuery reads the mode from the prefix', () => {
  assert.deepEqual(parseQuery('foot'), { mode: 'apps', q: 'foot' });
  assert.deepEqual(parseQuery(''), { mode: 'apps', q: '' });
  assert.deepEqual(parseQuery('w foot'), { mode: 'windows', q: 'foot' });
  assert.deepEqual(parseQuery('v hello'), { mode: 'clipboard', q: 'hello' });
  assert.deepEqual(parseQuery(': fire'), { mode: 'emoji', q: 'fire' });
  assert.deepEqual(parseQuery('= 1 + 2'), { mode: 'calculator', q: '1 + 2' });
  assert.deepEqual(parseQuery('> lo'), { mode: 'commands', q: 'lo' });
  assert.deepEqual(parseQuery('w '), { mode: 'windows', q: '' });
  assert.deepEqual(parseQuery('r 20m tea'), { mode: 'reminder', q: '20m tea' });
  assert.deepEqual(parseQuery('c moc'), { mode: 'colorschemes', q: 'moc' });
  assert.deepEqual(parseQuery('c '), { mode: 'colorschemes', q: '' });
});

test('a prefix letter without its space stays an app search', () => {
  assert.deepEqual(parseQuery('w'), { mode: 'apps', q: 'w' });
  assert.deepEqual(parseQuery('wine'), { mode: 'apps', q: 'wine' });
  assert.deepEqual(parseQuery('=1'), { mode: 'apps', q: '=1' });
  assert.deepEqual(parseQuery('c'), { mode: 'apps', q: 'c' });
  assert.deepEqual(parseQuery('code'), { mode: 'apps', q: 'code' });
});

test('windows rank by title then app_id, as rows with the window id', () => {
  const ws = [
    { id: 7, title: 'notes', app_id: 'foot' },
    { id: 3, title: 'foot', app_id: 'foot' },
    { id: 9, title: 'Mozilla', app_id: 'firefox' },
    { id: 4, title: null, app_id: null },
  ];
  assert.deepEqual(
    windowRows(ws, 'foot').map((r) => [r.title, r.detail, r.id]),
    [
      ['foot', 'foot', 3],
      ['notes', 'foot', 7],
    ],
  );
  assert.deepEqual(windowRows(ws, 'foot')[0].exec, ['niri', 'msg', 'action', 'focus-window', '--id', '3']);
});

test('commands filter by name, lock first for lo', () => {
  assert.deepEqual(commandRows('lo').map((r) => r.title), ['lock', 'Pick colour']);
  assert.deepEqual(commandRows('lock')[0].exec, ['qs', 'ipc', 'call', 'lock', 'lock']);
  assert.deepEqual(commandRows('theme')[0].exec, ['dots-call', 'launcher', 'mode', 'colorschemes']);
  assert.deepEqual(commandRows('record')[0].exec, ['qs', 'ipc', 'call', 'record', 'toggle']);
  assert.deepEqual(commandRows('sync')[0].exec, ['dots', 'sync']);
});

test('an empty commands query lists the five capture rows first, then the others in their own order', () => {
  assert.deepEqual(commandRows('').map((r) => r.title), [
    'Annotate region', 'Annotate clipboard image', 'Copy text from region (OCR)', 'Read QR code from region', 'Pick colour',
    'lock', 'theme', 'record', 'sync', 'Remote: mini', 'Remote: nuc', 'Remote: macbook',
  ]);
});

test('each machine lists a Remote row for the other two, each running dots-vnc with the name in its title', () => {
  const remotes = (machine) => commandRows('remote', undefined, machine).map((r) => [r.title, r.exec]);
  assert.deepEqual(remotes('macbook-m2'), [['Remote: mini', ['dots-vnc', 'mini']], ['Remote: nuc', ['dots-vnc', 'nuc']]]);
  assert.deepEqual(remotes('nuc'), [['Remote: macbook', ['dots-vnc', 'macbook']], ['Remote: mini', ['dots-vnc', 'mini']]]);
  assert.deepEqual(remotes('mac-mini-m2'), [['Remote: macbook', ['dots-vnc', 'macbook']], ['Remote: nuc', ['dots-vnc', 'nuc']]]);
});

test('a machine that is none of the three, like the install container or a nested session, lists all three Remote rows', () => {
  for (const machine of ['test', 'dev', 'unknown']) {
    assert.deepEqual(commandRows('remote', '/srv/b', machine).map((r) => r.exec), [
      ['/srv/b/dots-vnc', 'macbook'], ['/srv/b/dots-vnc', 'mini'], ['/srv/b/dots-vnc', 'nuc'],
    ]);
  }
});

test('each capture row runs dots-capture, and a row with a global key names it', () => {
  const row = (q) => commandRows(q)[0];
  assert.deepEqual([row('annotate region').exec, row('annotate region').key], [['dots-capture', 'annotate'], 'Mod+Shift+7']);
  assert.deepEqual([row('annotate clip').exec, row('annotate clip').key], [['dots-capture', 'annotate-clip'], undefined]);
  assert.deepEqual([row('ocr').exec, row('ocr').key], [['dots-capture', 'ocr'], 'Mod+Shift+6']);
  assert.deepEqual([row('qr').exec, row('qr').key], [['dots-capture', 'qr'], undefined]);
  assert.deepEqual([row('pick').exec, row('pick').key], [['dots-capture', 'colour'], undefined]);
});

test("given the shell's bin dir, a command row runs dots and dots-capture from it and the rest as they are", () => {
  const bin = '/srv/b';
  assert.deepEqual(commandRows('sync', bin)[0].exec, ['/srv/b/dots', 'sync']);
  assert.deepEqual(commandRows('ocr', bin)[0].exec, ['/srv/b/dots-capture', 'ocr']);
  assert.deepEqual(commandRows('lock', bin)[0].exec, ['qs', 'ipc', 'call', 'lock', 'lock']);
});

test('the calculator row is the formatted result, copied on Enter', () => {
  assert.deepEqual(calcRows('1440 * 1.25').map((r) => [r.title, r.copy]), [['1800', '1800']]);
  assert.deepEqual(calcRows('2 +'), []);
});

const zones = { home: 'Asia/Dhaka', zones: [
  { id: 'Asia/Dhaka', city: 'Dhaka', offset: 21600 }, { id: 'UTC', city: 'UTC', offset: 0 },
  { id: 'Europe/London', city: 'London', offset: 3600 }, { id: 'America/New_York', city: 'New York', offset: -14400 }] };

test('= 17:00 nyc is one row: the conversion, its day word as detail, the home time copied on Enter', () => {
  const now = Date.UTC(2026, 9, 22, 9, 12);
  assert.deepEqual(convertRows('17:00 nyc', now, zones).map((r) => [r.title, r.detail, r.copy, r.glyph]), [['17:00 New York = 03:00 Dhaka', 'tomorrow', '03:00', '=']]);
  assert.deepEqual(convertRows('09:30 london', now, zones).map((r) => [r.title, r.detail]), [['09:30 London = 14:30 Dhaka', 'London UTC+1 · Dhaka UTC+6']]);
  assert.deepEqual(convertRows('2 + 2', now, zones), []);
  assert.deepEqual(convertRows('17:00 nyc', now, null), []);
});

test('a window row keeps the icon its window was given, and calculator and command rows carry their prefix as a glyph', () => {
  assert.equal(windowRows([{ id: 1, title: 'a', app_id: 'foot', icon: 'image://icon/foot' }], '')[0].icon, 'image://icon/foot');
  assert.equal(calcRows('1 + 1')[0].glyph, '=');
  assert.equal(commandRows('lock')[0].glyph, '>');
});

test('a bare letter in the overview types itself, a shifted one its capital', () => {
  assert.equal(overviewChar('c', {}), 'c');
  assert.equal(overviewChar('A', {}), 'A');
  assert.equal(overviewChar('=', {}), '=');
});

test('a key with Ctrl, Alt or Mod in the overview types nothing', () => {
  assert.equal(overviewChar('\u0003', { ctrl: true }), '');
  assert.equal(overviewChar('c', { ctrl: true }), '');
  assert.equal(overviewChar('x', { alt: true }), '');
  assert.equal(overviewChar('o', { meta: true }), '');
});

test('a key with no text or a control character in the overview types nothing', () => {
  assert.equal(overviewChar('', {}), '');
  assert.equal(overviewChar('\u001b', {}), '');
  assert.equal(overviewChar('\r', {}), '');
  assert.equal(overviewChar('\t', {}), '');
  assert.equal(overviewChar('\u007f', {}), '');
});

// themes.json's entries, as the shell reads them: each scheme's tokens with its title and family.
const scheme = (name, title, family, mode, n = 0) => ({
  name, title, family, mode,
  color: { paper: `#00000${n}`, surface: `#11111${n}`, accent: `#22222${n}`, ink: '#FFFFFF', ansi: Array.from({ length: 16 }, (_, i) => `#${String(i).padStart(2, '0')}000${n}`) },
});
const SCHEMES = [
  scheme('artboard', 'Artboard', 'Artboard', 'light', 1),
  scheme('catppuccin-mocha', 'Catppuccin Mocha', 'Catppuccin', 'dark', 2),
  scheme('catppuccin-latte', 'Catppuccin Latte', 'Catppuccin', 'light', 3),
  scheme('rose-pine', 'Rosé Pine', 'Rosé Pine', 'dark', 4),
  scheme('rose-pine-moon', 'Rosé Pine Moon', 'Rosé Pine', 'dark', 5),
  scheme('rose-pine-dawn', 'Rosé Pine Dawn', 'Rosé Pine', 'light', 6),
  scheme('gruvbox-dark', 'Gruvbox Dark', 'Gruvbox', 'dark', 7),
  scheme('gruvbox-material-dark', 'Gruvbox Material Dark', 'Gruvbox Material', 'dark', 8),
  scheme('tokyo-night', 'Tokyo Night', 'Tokyo Night', 'dark', 9),
];
const titles = (rows) => rows.map((r) => r.title);

test('c with nothing typed lists every scheme by title', () => {
  assert.deepEqual(titles(schemeRows(SCHEMES, '', 'artboard')), [
    'Artboard', 'Catppuccin Latte', 'Catppuccin Mocha', 'Gruvbox Dark', 'Gruvbox Material Dark', 'Rosé Pine', 'Rosé Pine Dawn', 'Rosé Pine Moon', 'Tokyo Night',
  ]);
});

test('typing filters by title: moc leaves Catppuccin Mocha alone', () => {
  assert.deepEqual(titles(schemeRows(SCHEMES, 'moc', 'artboard')), ['Catppuccin Mocha']);
});

test('a family name lists all its variants, and rose finds Rosé with its accent folded', () => {
  assert.deepEqual(titles(schemeRows(SCHEMES, 'rose', 'artboard')), ['Rosé Pine', 'Rosé Pine Dawn', 'Rosé Pine Moon']);
  assert.deepEqual(titles(schemeRows(SCHEMES, 'ROSÉ', 'artboard')), ['Rosé Pine', 'Rosé Pine Dawn', 'Rosé Pine Moon']);
  assert.deepEqual(titles(schemeRows(SCHEMES, 'gruvbox', 'artboard')), ['Gruvbox Dark', 'Gruvbox Material Dark']);
  assert.deepEqual(titles(schemeRows([scheme('x', 'Latte', 'Catppuccin', 'light')], 'catpp', '')), ['Latte']);
});

test('a row says light or dark and draws paper, surface, accent and ANSI 1, 2, 3 and 5', () => {
  const [row] = schemeRows(SCHEMES, 'mocha', 'artboard');
  assert.equal(row.name, 'catppuccin-mocha');
  assert.equal(row.detail, 'dark');
  assert.deepEqual(row.swatches, ['#000002', '#111112', '#222222', '#010002', '#020002', '#030002', '#050002']);
});

test('only the current scheme is marked', () => {
  const rows = schemeRows(SCHEMES, '', 'artboard');
  assert.deepEqual(rows.filter((r) => r.current).map((r) => r.name), ['artboard']);
  assert.deepEqual(schemeRows(SCHEMES, '', 'nope').filter((r) => r.current), []);
});

test('Enter on a row runs dots colorscheme from the bin beside the shell', () => {
  const [row] = schemeRows(SCHEMES, 'moc', 'artboard', '/b');
  assert.deepEqual(row.exec, ['/b/dots', 'colorscheme', 'catppuccin-mocha']);
  assert.equal(row.stamp, true);
});

// dots colorscheme times the switch from DOTS_SWITCH_T0, so the key press stamps it, not the row.
test('a stamped row runs under env with the key press time; any other row runs as it is', () => {
  assert.deepEqual(stampedExec({ exec: ['/b/dots', 'colorscheme', 'nord'], stamp: true }, 1234), ['env', 'DOTS_SWITCH_T0=1234', '/b/dots', 'colorscheme', 'nord']);
  assert.deepEqual(stampedExec({ exec: ['dots', 'sync'] }, 1234), ['dots', 'sync']);
});

// themes.json is a file any process can write, so an entry the shell would refuse gets no row, and a forged title draws on one line.
test('schemeList keeps every rendered scheme with its title and family, and drops what the shell would refuse', (t) => {
  const state = mkdtempSync(join(tmpdir(), 'dots-launcher-'));
  t.after(() => rmSync(state, { recursive: true, force: true }));
  execFileSync('node', [new URL('./colorscheme-render.mjs', import.meta.url).pathname, 'artboard'], { env: { ...process.env, XDG_STATE_HOME: state } });
  const rendered = JSON.parse(readFileSync(join(state, 'dots/theme-out/themes.json'), 'utf8'));
  const list = schemeList(rendered);
  assert.equal(list.length, rendered.length);
  const mocha = list.find((s) => s.name === 'catppuccin-mocha');
  assert.equal(mocha.title, 'Catppuccin Mocha');
  assert.equal(mocha.family, 'Catppuccin');
  assert.equal(mocha.color.ansi.length, 16);
  const noAnsi = { ...mocha, name: 'noansi', color: { ...mocha.color } };
  delete noAnsi.color.ansi;
  const forged = { ...rendered[0], name: 'forged', title: 'Ev\nil\u202E', family: 7 };
  const numbered = { ...rendered[0], name: 5, title: 7 };
  const out = schemeList([noAnsi, null, 'x', forged, numbered]);
  assert.deepEqual(out.map((s) => s.name), ['forged']);
  assert.equal(out[0].title, 'Ev il');
  assert.equal(out[0].family, '');
  assert.deepEqual(schemeList({ not: 'a list' }), []);
});

test('the selection scrolls the eight visible rows: down past the last row moves the window, up past the first moves it back', () => {
  assert.deepEqual(scroll(0, 0, 1, 40, 8), { top: 0, selected: 1 });
  assert.deepEqual(scroll(0, 7, 1, 40, 8), { top: 1, selected: 7 });
  assert.deepEqual(scroll(32, 7, 1, 40, 8), { top: 32, selected: 7 });
  assert.deepEqual(scroll(5, 0, -1, 40, 8), { top: 4, selected: 0 });
  assert.deepEqual(scroll(0, 0, -1, 40, 8), { top: 0, selected: 0 });
  assert.deepEqual(scroll(0, 2, 1, 3, 8), { top: 0, selected: 2 });
  assert.deepEqual(scroll(0, 0, 1, 0, 8), { top: 0, selected: 0 });
  // A row deleted from the bottom of a scrolled list: no move, and the window comes back onto what is left.
  assert.deepEqual(scroll(4, 7, 0, 4, 8), { top: 0, selected: 3 });
  assert.deepEqual(scroll(2, 7, 0, 9, 8), { top: 1, selected: 7 });
});

test('a wheel notch moves the window three rows and keeps the selected row while it stays shown', () => {
  // A notch is 120 of Qt's angle, down when negative.
  assert.deepEqual(wheel({ top: 0, selected: 5, rest: 0 }, -120, 40, 8), { top: 3, selected: 2, rest: 0 });
  assert.deepEqual(wheel({ top: 3, selected: 2, rest: 0 }, 120, 40, 8), { top: 0, selected: 5, rest: 0 });
  // A row that scrolls out of view hands the selection to the nearest shown row, so Enter runs a row in view.
  assert.deepEqual(wheel({ top: 0, selected: 1, rest: 0 }, -120, 40, 8), { top: 3, selected: 0, rest: 0 });
  assert.deepEqual(wheel({ top: 3, selected: 6, rest: 0 }, 120, 40, 8), { top: 0, selected: 7, rest: 0 });
  // It stops at either end, and a list that fits does not move.
  assert.deepEqual(wheel({ top: 31, selected: 0, rest: 0 }, -360, 40, 8), { top: 32, selected: 0, rest: 0 });
  assert.deepEqual(wheel({ top: 1, selected: 0, rest: 0 }, 360, 40, 8), { top: 0, selected: 1, rest: 0 });
  assert.deepEqual(wheel({ top: 0, selected: 2, rest: 0 }, -120, 5, 8), { top: 0, selected: 2, rest: 0 });
});

test("a touchpad's small angles add up to a row a third of a notch", () => {
  const a = wheel({ top: 0, selected: 0, rest: 0 }, -15, 40, 8);
  assert.deepEqual(a, { top: 0, selected: 0, rest: -15 });
  const b = wheel(a, -30, 40, 8);
  assert.deepEqual(b, { top: 1, selected: 0, rest: -5 });
});
