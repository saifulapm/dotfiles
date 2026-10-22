import { test } from 'node:test';
import assert from 'node:assert/strict';
import { answerLine, appName, dateText, headingText, oneLine, parseBookmarks, parseRequest, pickerKeys, sizeText, sortRows } from './picker.mjs';

test('a request line keeps every field the backend sends', () => {
  const r = parseRequest('{"mode":"open","multiple":false,"title":"Open File","app":"chromium-browser","folder":"/home/s/Downloads","name":"","filters":[{"name":"Images","globs":["*.png"],"mimes":[]}],"filter":0,"accept":""}');
  assert.deepEqual(r, {
    mode: 'open',
    multiple: false,
    title: 'Open File',
    app: 'chromium-browser',
    folder: '/home/s/Downloads',
    name: '',
    filters: [{ name: 'Images', globs: ['*.png'], mimes: [] }],
    filter: 0,
    accept: '',
  });
});

test('a line that is not a request parses as null', () => {
  assert.equal(parseRequest('{"mode":"open"'), null);
  assert.equal(parseRequest('not json'), null);
  assert.equal(parseRequest('[1,2]'), null);
  assert.equal(parseRequest('{"mode":"delete"}'), null);
  assert.equal(parseRequest(''), null);
});

test('the answer is one JSON line: a chosen path, a cancel, an unreadable request', () => {
  assert.equal(answerLine(0, ['/home/s/Downloads/a b #1 %41 ü.txt']), '{"response":0,"paths":["/home/s/Downloads/a b #1 %41 ü.txt"]}\n');
  assert.equal(answerLine(1, []), '{"response":1,"paths":[]}\n');
  assert.equal(answerLine(2, []), '{"response":2,"paths":[]}\n');
});

test('folders come first, then files, each by name whatever its case', () => {
  const rows = [
    { name: 'report-q3.pdf', dir: false },
    { name: 'Taildrop', dir: true },
    { name: 'IMG_2041.HEIC', dir: false },
    { name: 'Fedora-Asahi-Remix-43.iso', dir: false },
    { name: 'screenshots', dir: true },
    { name: 'lareys-brief.pdf', dir: false },
    { name: 'invoices-2026', dir: true },
  ];
  assert.deepEqual(
    sortRows(rows).map((r) => r.name),
    ['invoices-2026', 'screenshots', 'Taildrop', 'Fedora-Asahi-Remix-43.iso', 'IMG_2041.HEIC', 'lareys-brief.pdf', 'report-q3.pdf'],
  );
});

test('sizes read as the boards write them, and a folder counts its items', () => {
  assert.equal(sizeText({ dir: false, size: 3100000 }), '3.1 MB');
  assert.equal(sizeText({ dir: false, size: 184000 }), '184 KB');
  assert.equal(sizeText({ dir: false, size: 96000000 }), '96 MB');
  assert.equal(sizeText({ dir: false, size: 2400000000 }), '2.4 GB');
  assert.equal(sizeText({ dir: false, size: 512 }), '512 B');
  assert.equal(sizeText({ dir: true, count: 8 }), '8 items');
  assert.equal(sizeText({ dir: true, count: 1 }), '1 item');
});

test('a modified date in each voice: Paper times today only, Artboard pads the day, Blueprint is ISO', () => {
  const now = new Date(2026, 9, 18, 15, 12).getTime();
  const today = new Date(2026, 9, 18, 14, 7).getTime();
  const earlier = new Date(2026, 9, 9, 11, 20).getTime();
  const lastYear = new Date(2025, 1, 2, 8, 5).getTime();
  assert.equal(dateText('caps', today, now), '18 Oct 14:07');
  assert.equal(dateText('caps', earlier, now), '9 Oct');
  assert.equal(dateText('caps', lastYear, now), '2 Feb 2025');
  assert.equal(dateText('plain', earlier, now), '09 Oct');
  assert.equal(dateText('plain', today, now), '18 Oct');
  assert.equal(dateText('plain', lastYear, now), '02 Feb 2025');
  assert.equal(dateText('bracket', earlier, now), '2026-10-09 11:20');
});

test('the heading names the app in each voice, and stands alone without one', () => {
  assert.equal(headingText('caps', 'Chromium'), 'OPEN FILE · CHROMIUM');
  assert.equal(headingText('plain', 'Chromium'), 'Open file · Chromium');
  assert.equal(headingText('bracket', 'Chromium'), 'OPEN FILE // CHROMIUM');
  assert.equal(headingText('caps', ''), 'OPEN FILE');
  assert.equal(headingText('plain', ''), 'Open file');
  assert.equal(headingText('bracket', ''), 'OPEN FILE');
});

test('the key strip in each voice', () => {
  const strip = (v) => pickerKeys(v).map((k) => (k.key + ' ' + k.word).trim()).join(' · ');
  assert.equal(strip('plain'), '↵ open · tab places · ctrl+l path · ctrl+h hidden · ctrl+space select · esc');
  assert.equal(strip('caps'), '↵ OPEN · TAB PLACES · ⌃L PATH · ⌃H HIDDEN · ⌃␣ SELECT · ESC');
  assert.equal(strip('bracket'), '[↵] OPEN · [TAB] PLACES · [⌃L] PATH · [⌃H] HIDDEN · [⌃␣] SELECT · [ESC]');
});

test('text another program controls draws as one line, without controls or bidi marks', () => {
  assert.equal(oneLine('evil\nname‮txt.exe\u001b[31m‏'), 'evil nametxt.exe [31m');
  assert.equal(oneLine('  tab\there  '), 'tab here');
  assert.equal(oneLine(''), '');
  assert.equal(oneLine(undefined), '');
});

test('an app id is named by its desktop entry, else by the id itself', () => {
  const apps = [{ id: 'chromium-browser', name: 'Chromium Web Browser' }];
  assert.equal(appName(apps, 'Chromium-Browser'), 'Chromium Web Browser');
  assert.equal(appName(apps, 'org.example.Unknown'), 'org.example.Unknown');
  assert.equal(appName(apps, ''), '');
});

test('GTK bookmarks become pins: the URI decoded, the label or else the folder name', () => {
  const text = 'file:///home/s/Codes/lareys\nfile:///home/s/Documents/My%20Invoices%20%C3%BC Invoices\n\nsftp://host/x\n';
  assert.deepEqual(parseBookmarks(text), [
    { path: '/home/s/Codes/lareys', label: 'lareys' },
    { path: '/home/s/Documents/My Invoices ü', label: 'Invoices' },
  ]);
  assert.deepEqual(parseBookmarks(''), []);
});
