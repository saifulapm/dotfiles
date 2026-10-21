import { test } from 'node:test';
import assert from 'node:assert/strict';
import { rank, parseQuery, windowRows, commandRows, calcRows } from './launcher.mjs';

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
    'lock', 'theme', 'record', 'sync',
  ]);
});

test('each capture row runs dots-capture, and a row with a global key names it', () => {
  const row = (q) => commandRows(q)[0];
  assert.deepEqual([row('annotate region').exec, row('annotate region').key], [['dots-capture', 'annotate'], 'Mod+Shift+7']);
  assert.deepEqual([row('annotate clip').exec, row('annotate clip').key], [['dots-capture', 'annotate-clip'], undefined]);
  assert.deepEqual([row('ocr').exec, row('ocr').key], [['dots-capture', 'ocr'], 'Mod+Shift+6']);
  assert.deepEqual([row('qr').exec, row('qr').key], [['dots-capture', 'qr'], undefined]);
  assert.deepEqual([row('pick').exec, row('pick').key], [['dots-capture', 'colour'], undefined]);
});

test('the calculator row is the formatted result, copied on Enter', () => {
  assert.deepEqual(calcRows('1440 * 1.25').map((r) => [r.title, r.copy]), [['1800', '1800']]);
  assert.deepEqual(calcRows('2 +'), []);
});

test('a window row keeps the icon its window was given, and calculator and command rows carry their prefix as a glyph', () => {
  assert.equal(windowRows([{ id: 1, title: 'a', app_id: 'foot', icon: 'image://icon/foot' }], '')[0].icon, 'image://icon/foot');
  assert.equal(calcRows('1 + 1')[0].glyph, '=');
  assert.equal(commandRows('lock')[0].glyph, '>');
});
