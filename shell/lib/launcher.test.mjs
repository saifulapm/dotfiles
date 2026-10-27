import { test } from 'node:test';
import assert from 'node:assert/strict';
import { rank, parseQuery, windowRows, commandRows, calcRows, convertRows, overviewChar } from './launcher.mjs';

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
});

test('a prefix letter without its space stays an app search', () => {
  assert.deepEqual(parseQuery('w'), { mode: 'apps', q: 'w' });
  assert.deepEqual(parseQuery('wine'), { mode: 'apps', q: 'wine' });
  assert.deepEqual(parseQuery('=1'), { mode: 'apps', q: '=1' });
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
  assert.deepEqual(commandRows('theme')[0].exec, ['qs', 'ipc', 'call', 'themes', 'open']);
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
