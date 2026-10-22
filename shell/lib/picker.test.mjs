import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, rmSync, symlinkSync, writeFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { answerLine, appName, chipText, completionHead, completions, countText, dateText, footText, headingText, LIST_SCRIPT, markedPaths, matchText, nameText, oneLine, parseBookmarks, parseRequest, pathKeys, pickerKeys, placeMatches, previewText, saveNotice, saveProblem, shownRows, SIZE_SCRIPT, sizeText, sortRows, splitPath, stampText, toggleMark } from './picker.mjs';

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

test('a save request heads the card Save as, in each voice', () => {
  assert.equal(headingText('caps', 'kak', 'save'), 'SAVE AS · KAK');
  assert.equal(headingText('plain', 'kak', 'save'), 'Save as · kak');
  assert.equal(headingText('bracket', 'kak', 'save'), 'SAVE AS // KAK');
  assert.equal(headingText('plain', '', 'save'), 'Save as');
});

test('the key strip in each voice', () => {
  const strip = (v) => pickerKeys(v).map((k) => (k.key + ' ' + k.word).trim()).join(' · ');
  assert.equal(strip('plain'), '↵ open · tab places · ctrl+l path · ctrl+h hidden · ctrl+space select · esc');
  assert.equal(strip('caps'), '↵ OPEN · TAB PLACES · ⌃L PATH · ⌃H HIDDEN · ⌃␣ SELECT · ESC');
  assert.equal(strip('bracket'), '[↵] OPEN · [TAB] PLACES · [⌃L] PATH · [⌃H] HIDDEN · [⌃␣] SELECT · [ESC]');
});

test("a several-files strip marks in Paper's words, and selects in Artboard's and Blueprint's", () => {
  const strip = (v) => pickerKeys(v, 'open', true).map((k) => (k.key + ' ' + k.word).trim()).join(' · ');
  assert.equal(strip('caps'), '↵ OPEN · TAB PLACES · ⌃L PATH · ⌃H HIDDEN · ⌃␣ MARK · ESC');
  assert.equal(strip('plain'), '↵ open · tab places · ctrl+l path · ctrl+h hidden · ctrl+space select · esc');
  assert.equal(strip('bracket'), '[↵] OPEN · [TAB] PLACES · [⌃L] PATH · [⌃H] HIDDEN · [⌃␣] SELECT · [ESC]');
});

test('the heading chip counts the marked files, or says a folder request lists folders only', () => {
  assert.equal(chipText('plain', 'open', 3), '3 marked');
  assert.equal(chipText('caps', 'open', 1), '1 MARKED');
  assert.equal(chipText('bracket', 'open', 2), '2 MARKED');
  assert.equal(chipText('caps', 'open', 0), '');
  assert.equal(chipText('plain', 'folder', 0), 'folders only');
  assert.equal(chipText('bracket', 'folder', 0), 'FOLDERS ONLY');
  assert.equal(chipText('caps', 'save', 0), '');
});

test('the save strip saves and selects nothing', () => {
  const strip = (v) => pickerKeys(v, 'save').map((k) => (k.key + ' ' + k.word).trim()).join(' · ');
  assert.equal(strip('plain'), '↵ save · tab places · ctrl+l path · ctrl+h hidden · esc');
  assert.equal(strip('caps'), '↵ SAVE · TAB PLACES · ⌃L PATH · ⌃H HIDDEN · ESC');
  assert.equal(strip('bracket'), '[↵] SAVE · [TAB] PLACES · [⌃L] PATH · [⌃H] HIDDEN · [ESC]');
});

test('a name to save is refused when empty, a path, a dot name or a folder, and asked about when it exists', () => {
  const entries = [{ name: 'drafts', dir: true }, { name: 'report.pdf', dir: false }, { name: '.env', dir: false }];
  assert.equal(saveProblem('notes 2.txt', entries), '');
  assert.equal(saveProblem('report.pdf', entries), 'exists');
  assert.equal(saveProblem('.env', entries), 'exists');
  assert.equal(saveProblem('', entries), 'empty');
  assert.equal(saveProblem('a/b.txt', entries), 'slash');
  assert.equal(saveProblem('.', entries), 'dots');
  assert.equal(saveProblem('..', entries), 'dots');
  assert.equal(saveProblem('drafts', entries), 'folder');
});

test('the save notice replaces the strip in the error voice; the name keeps its case', () => {
  const said = (v, tag, name) => {
    const n = saveNotice(v, tag, name);
    return [n.say].concat(n.keys.map((k) => (k.key + ' ' + k.word).trim())).join(' · ');
  };
  assert.equal(said('plain', 'exists', 'report.pdf'), 'report.pdf exists · ↵ replace · esc keep');
  assert.equal(said('caps', 'exists', 'report.pdf'), 'report.pdf exists · ↵ REPLACE · ESC KEEP');
  assert.equal(said('bracket', 'exists', 'Report.pdf'), '! Report.pdf EXISTS · [↵] REPLACE · [ESC] KEEP');
  assert.equal(said('plain', 'empty', ''), 'type a name to save as');
  assert.equal(said('plain', 'slash', 'a/b'), 'a name cannot hold /');
  assert.equal(said('caps', 'dots', '..'), '.. is not a file name');
  assert.equal(said('bracket', 'folder', 'drafts'), '! drafts IS A FOLDER');
});

test('a typed name loses controls and bidi marks and keeps its spaces', () => {
  assert.equal(nameText('notes '), 'notes ');
  assert.equal(nameText('a\u202eb\u200fc\u0007d\n'), 'abcd');
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

const places = [
  { path: '/home/s', label: 'Home' },
  { path: '/home/s/Downloads', label: 'Downloads' },
  { path: '/home/s/Codes', label: 'Codes' },
  { path: '/home/s/Pictures', label: 'Pictures' },
  { path: '/home/s/Codes/lareys', label: 'lareys' },
];

test('a query matches places whose names start with it, whatever its case', () => {
  assert.deepEqual(placeMatches(places, 'down'), [{ index: 1, length: 4 }]);
  assert.deepEqual(placeMatches(places, 'P'), [{ index: 3, length: 1 }]);
  assert.deepEqual(placeMatches(places, 'o'), []);
  assert.deepEqual(placeMatches(places, '2041'), []);
  assert.deepEqual(placeMatches(places, ''), []);
});

const entries = [
  { name: 'report.pdf', dir: false, mime: 'application/pdf' },
  { name: 'shot.PNG', dir: false, mime: 'image/png' },
  { name: 'IMG_2041.HEIC', dir: false, mime: 'image/heic' },
  { name: 'Taildrop', dir: true, mime: '' },
  { name: '.config', dir: true, mime: '' },
  { name: '.hidden.txt', dir: false, mime: 'text/plain' },
];
const names = (rows) => rows.map((r) => r.name);

test('the rows shown: dotfiles only when asked, then the query, folders first', () => {
  assert.deepEqual(names(shownRows(entries, { hidden: false, filter: null, query: '' })), ['Taildrop', 'IMG_2041.HEIC', 'report.pdf', 'shot.PNG']);
  assert.deepEqual(names(shownRows(entries, { hidden: true, filter: null, query: '' })), ['.config', 'Taildrop', '.hidden.txt', 'IMG_2041.HEIC', 'report.pdf', 'shot.PNG']);
  assert.deepEqual(names(shownRows(entries, { hidden: false, filter: null, query: '2041' })), ['IMG_2041.HEIC']);
  assert.deepEqual(names(shownRows(entries, { hidden: false, filter: null, query: 'heic' })), ['IMG_2041.HEIC']);
});

test("an app's filter hides files its globs or mimes miss, never folders", () => {
  const images = { name: 'Images', globs: ['*.png', '*.jpg'], mimes: [] };
  assert.deepEqual(names(shownRows(entries, { hidden: false, filter: images, query: '' })), ['Taildrop', 'shot.PNG']);
  const byMime = { name: 'Pictures', globs: [], mimes: ['image/*'] };
  assert.deepEqual(names(shownRows(entries, { hidden: false, filter: byMime, query: '' })), ['Taildrop', 'IMG_2041.HEIC', 'shot.PNG']);
  const pdf = { name: 'PDF', globs: [], mimes: ['application/pdf'] };
  assert.deepEqual(names(shownRows(entries, { hidden: false, filter: pdf, query: '' })), ['Taildrop', 'report.pdf']);
  const all = { name: 'All', globs: ['*'], mimes: [] };
  assert.deepEqual(names(shownRows(entries, { hidden: false, filter: all, query: '' })), ['Taildrop', 'IMG_2041.HEIC', 'report.pdf', 'shot.PNG']);
  const odd = { name: 'Odd', globs: ['a+b?.[ch]'], mimes: [] };
  assert.deepEqual(names(shownRows([{ name: 'a+b1.c', dir: false }, { name: 'aab1.c', dir: false }], { hidden: false, filter: odd, query: '' })), ['a+b1.c']);
});

test('a typed path splits into the folder to list and the name begun in it, ~ as Home', () => {
  assert.deepEqual(splitPath('~/Codes/la', '/home/s', '/tmp'), { parent: '/home/s/Codes', tail: 'la' });
  assert.deepEqual(splitPath('~/', '/home/s', '/tmp'), { parent: '/home/s', tail: '' });
  assert.deepEqual(splitPath('~', '/home/s', '/tmp'), { parent: '/home/s', tail: '' });
  assert.deepEqual(splitPath('/etc/sy', '/home/s', '/tmp'), { parent: '/etc', tail: 'sy' });
  assert.deepEqual(splitPath('/et', '/home/s', '/tmp'), { parent: '/', tail: 'et' });
  assert.deepEqual(splitPath('sub/x', '/home/s', '/tmp'), { parent: '/tmp/sub', tail: 'x' });
  assert.deepEqual(splitPath('', '/home/s', '/tmp'), { parent: '/tmp', tail: '' });
});

test('completions are folders that start with the tail, most recently changed first', () => {
  const list = [
    { name: 'laravel-demo', dir: true, mtime: 100 },
    { name: 'lareys', dir: true, mtime: 300 },
    { name: 'lareys-mobile', dir: true, mtime: 200 },
    { name: 'lareys-notes.txt', dir: false, mtime: 400 },
    { name: 'dotfiles', dir: true, mtime: 500 },
    { name: '.lab', dir: true, mtime: 600 },
  ];
  assert.deepEqual(names(completions(list, 'la')), ['lareys', 'lareys-mobile', 'laravel-demo']);
  assert.deepEqual(names(completions(list, '')), ['dotfiles', 'lareys', 'lareys-mobile', 'laravel-demo']);
  assert.deepEqual(names(completions(list, '.l')), ['.lab']);
});

test('the typed match in each voice: Paper and Blueprint count, Artboard names the place', () => {
  assert.equal(matchText('caps', 'places', 1, 'Downloads'), '1 PLACE');
  assert.equal(matchText('caps', 'places', 3, ''), '3 PLACES');
  assert.equal(matchText('bracket', 'places', 1, 'Downloads'), '1 PLACE');
  assert.equal(matchText('plain', 'places', 1, 'Downloads'), '→ Downloads');
  assert.equal(matchText('plain', 'places', 2, ''), '2 places');
  assert.equal(matchText('caps', 'path', 4, ''), '4 MATCHES');
  assert.equal(matchText('bracket', 'path', 1, ''), '1 MATCH');
  assert.equal(matchText('plain', 'path', 4, ''), '');
});

test('the folder row counts its items, names the filter and says whether dotfiles show', () => {
  assert.equal(countText('plain', 11, '', false), '11 items · hidden off');
  assert.equal(countText('plain', 1, 'Images', true), '1 item · Images · hidden on');
  assert.equal(countText('caps', 9, 'Images', false), '9 ITEMS · IMAGES · HIDDEN OFF');
  assert.equal(countText('bracket', 9, '', true), '9 ITEMS · HIDDEN ON');
});

test('a folder request counts folders with files hidden, and a save counts what the folder holds', () => {
  assert.equal(countText('plain', 6, '', false, 'folder'), '6 folders · files hidden');
  assert.equal(countText('caps', 1, '', true, 'folder'), '1 FOLDER · FILES HIDDEN');
  assert.equal(countText('bracket', 6, '', false, 'folder'), '6 FOLDERS · FILES HIDDEN');
  assert.equal(countText('plain', 7, '', false, 'save'), '7 items');
  assert.equal(countText('caps', 7, '', true, 'save'), '7 ITEMS');
  assert.equal(countText('bracket', 1, '', false, 'save'), '1 ITEM');
});

test('the completions heading in each voice', () => {
  assert.equal(completionHead('plain', 3, '~/Codes', 'la'), '3 folders in ~/Codes start with la');
  assert.equal(completionHead('plain', 1, '~/Codes', 'la'), '1 folder in ~/Codes starts with la');
  assert.equal(completionHead('caps', 3, '~/Codes', 'la'), 'FOLDERS');
  assert.equal(completionHead('bracket', 3, '~/Codes', 'la'), 'COMPLETING IN ~/Codes');
});

test('the path mode key strip in each voice', () => {
  const strip = (v) => pathKeys(v).map((k) => (k.key + ' ' + k.word).trim()).join(' · ');
  assert.equal(strip('plain'), 'tab complete · ↵ go · ctrl+l filter · esc');
  assert.equal(strip('caps'), '↵ GO · TAB COMPLETE · ⌃L BACK TO LIST · ESC');
  assert.equal(strip('bracket'), '[↵] GO · [TAB] COMPLETE · [⌃L] BACK TO LIST · [ESC]');
});

test("the preview's meta lines in each theme's idiom: Paper's and Blueprint's labels, Blueprint's header, Artboard's badge and plain lines", () => {
  const heic = { name: 'IMG_2041.HEIC', dir: false, size: 2800000, mime: 'image/heic', mtime: new Date(2026, 9, 18, 14, 7).getTime() };
  assert.deepEqual(previewText('caps', heic, 4032, 3024), {
    head: '',
    kind: '',
    badge: '',
    lines: [
      { label: 'DIMENSIONS', value: '4032 × 3024' },
      { label: 'SIZE', value: '2.8 MB' },
      { label: 'MODIFIED', value: '18 Oct 2026 · 14:07' },
    ],
  });
  assert.deepEqual(previewText('plain', heic, 4032, 3024), {
    head: '',
    kind: '',
    badge: 'HEIC',
    lines: [
      { label: '', value: '4032 × 3024 px' },
      { label: '', value: '2.8 MB' },
      { label: '', value: '18 Oct 2026, 14:07' },
    ],
  });
  assert.deepEqual(previewText('bracket', heic, 4032, 3024), {
    head: 'PREVIEW',
    kind: 'IMAGE',
    badge: '',
    lines: [
      { label: 'DIMENSIONS', value: '4032 × 3024' },
      { label: 'SIZE', value: '2.8 MB' },
      { label: 'MODIFIED', value: '2026-10-18 14:07' },
    ],
  });
  // A file without a size read from its header has no dimensions line at all.
  const pdf = { name: 'report.pdf', dir: false, size: 184000, mime: 'application/pdf', mtime: new Date(2026, 9, 14, 16, 41).getTime() };
  assert.deepEqual(previewText('bracket', pdf, 0, 0), {
    head: 'PREVIEW',
    kind: 'FILE',
    badge: '',
    lines: [
      { label: 'SIZE', value: '184 KB' },
      { label: 'MODIFIED', value: '2026-10-14 16:41' },
    ],
  });
  assert.equal(previewText('plain', pdf, 0, 0).badge, 'PDF');
  assert.equal(previewText('plain', { name: 'Makefile', dir: false, size: 10, mime: '', mtime: 0 }, 0, 0).badge, '');
});

test('the full date in each voice', () => {
  const at = new Date(2026, 9, 14, 16, 41).getTime();
  assert.equal(stampText('caps', at), '14 Oct 2026 · 16:41');
  assert.equal(stampText('plain', at), '14 Oct 2026, 16:41');
  assert.equal(stampText('bracket', at), '2026-10-14 16:41');
});

test('an app that allows several files heads the card Open files, and a folder request Choose folder', () => {
  assert.equal(headingText('caps', 'Chromium', 'open', true), 'OPEN FILES · CHROMIUM');
  assert.equal(headingText('plain', 'Chromium', 'open', true), 'Open files · Chromium');
  assert.equal(headingText('bracket', 'Chromium', 'open', true), 'OPEN FILES // CHROMIUM');
  assert.equal(headingText('caps', 'Chromium', 'folder'), 'CHOOSE FOLDER · CHROMIUM');
  assert.equal(headingText('plain', 'Chromium', 'folder'), 'Choose folder · Chromium');
  assert.equal(headingText('bracket', 'Chromium', 'folder'), 'CHOOSE FOLDER // CHROMIUM');
  assert.equal(headingText('plain', '', 'folder'), 'Choose folder');
});

test('the folder strip enters with Enter and chooses with ctrl+Enter', () => {
  const strip = (v) => pickerKeys(v, 'folder').map((k) => (k.key + ' ' + k.word).trim()).join(' · ');
  assert.equal(strip('plain'), '↵ enter folder · ctrl+↵ choose this folder · esc');
  assert.equal(strip('caps'), '↵ ENTER FOLDER · ⌃↵ CHOOSE THIS FOLDER · ESC');
  assert.equal(strip('bracket'), '[↵] ENTER FOLDER · [⌃↵] CHOOSE THIS FOLDER · [ESC]');
});

test('a folder request lists only folders, dot folders when shown', () => {
  const entries = [{ name: 'notes.txt', dir: false }, { name: 'lareys', dir: true }, { name: '.config', dir: true }, { name: 'Codes', dir: true }];
  assert.deepEqual(shownRows(entries, { hidden: false, filter: null, query: '', folders: true }).map((r) => r.name), ['Codes', 'lareys']);
  assert.deepEqual(shownRows(entries, { hidden: true, filter: null, query: '', folders: true }).map((r) => r.name), ['.config', 'Codes', 'lareys']);
});

test('ctrl+space marks and unmarks a file, never a folder', () => {
  assert.deepEqual(toggleMark([], { name: 'b.png', dir: false }), ['b.png']);
  assert.deepEqual(toggleMark(['a.png', 'b.png'], { name: 'a.png', dir: false }), ['b.png']);
  assert.deepEqual(toggleMark(['a.png'], { name: 'shots', dir: true }), ['a.png']);
  assert.deepEqual(toggleMark(['a.png'], null), ['a.png']);
});

test('a name that is not UTF-8 is never marked, as its path would name another file', () => {
  assert.deepEqual(toggleMark(['a.png'], { name: 'caf\uFFFD.txt', dir: false, undecodable: true }), ['a.png']);
});

test('the marked files answer in list order, a file the query hides too', () => {
  const entries = [{ name: 'c.png', dir: false }, { name: 'shots', dir: true }, { name: 'A.png', dir: false }, { name: 'b.png', dir: false }];
  assert.deepEqual(markedPaths(entries, ['c.png', 'A.png', 'b.png'], '/home/s/Downloads'), ['/home/s/Downloads/A.png', '/home/s/Downloads/b.png', '/home/s/Downloads/c.png']);
  assert.deepEqual(markedPaths(entries, ['b.png'], '/'), ['/b.png']);
});

test('the footer line: how many are marked, or the folder ctrl+Enter chooses', () => {
  assert.equal(footText('plain', 'open', 3, '~/Downloads'), '3 selected · ctrl+↵ open all');
  assert.equal(footText('caps', 'open', 3, '~/Downloads'), '3 SELECTED · ⌃↵ OPEN ALL');
  assert.equal(footText('bracket', 'open', 1, '~/Downloads'), '1 SELECTED · [⌃↵] OPEN ALL');
  assert.equal(footText('plain', 'open', 0, '~/Downloads'), '');
  assert.equal(footText('plain', 'folder', 0, '~/Codes'), 'ctrl+↵ chooses ~/Codes, the folder you are in');
  assert.equal(footText('caps', 'folder', 0, '~/Codes'), 'THIS FOLDER ~/Codes');
  assert.equal(footText('bracket', 'folder', 0, '~/Codes'), 'THIS FOLDER ~/Codes');
});

// Only the header bytes each format keeps its size in; the rest of a fixture is filler.
test("the size script reads an image's true size from its header, and nothing from a PDF or a cut file", () => {
  const dir = mkdtempSync(join(tmpdir(), 'picker-size-'));
  const u16be = (n) => [n >> 8, n & 255];
  const u16le = (n) => [n & 255, n >> 8];
  const u24le = (n) => [n & 255, (n >> 8) & 255, n >> 16];
  const u32be = (n) => [n >>> 24, (n >> 16) & 255, (n >> 8) & 255, n & 255];
  const u32le = (n) => u32be(n).reverse();
  const ascii = (s) => [...s].map((c) => c.charCodeAt(0));
  // An APP1 of junk before the tables, so the reader walks segments to reach the frame header.
  const jpeg = (sof, junk) => [0xff, 0xd8, 0xff, 0xe1, ...u16be(junk + 2), ...new Array(junk).fill(7), 0xff, 0xdb, 0, 4, 1, 2, 0xff, 0xc4, 0, 3, 9, 0xff, sof, 0, 17, 8, ...u16be(3024), ...u16be(4032), 3, 1, 0x22, 0, 2, 0x11, 1, 3, 0x11, 1, 0xff, 0xda];
  const riff = (chunk, body) => [...ascii('RIFF'), ...u32le(4 + 8 + body.length), ...ascii('WEBP'), ...ascii(chunk), ...u32le(body.length), ...body];
  const files = {
    'shot.png': [0x89, ...ascii('PNG\r\n\x1a\n'), 0, 0, 0, 13, ...ascii('IHDR'), ...u32be(1600), ...u32be(1200), 8, 2, 0, 0, 0, 1, 2, 3, 4],
    'base.jpg': jpeg(0xc0, 9000),
    'prog.jpg': jpeg(0xc2, 30),
    'anim.gif': [...ascii('GIF89a'), ...u16le(320), ...u16le(240), 0xf7, 0, 0],
    'lossy.webp': riff('VP8 ', [0, 0, 0, 0x9d, 0x01, 0x2a, ...u16le(800), ...u16le(600), 0, 0]),
    'lossless.webp': riff('VP8L', [0x2f, ...u32le(1023 | (767 << 14)), 0]),
    'extended.webp': riff('VP8X', [16, 0, 0, 0, ...u24le(4031), ...u24le(3023)]),
    'report.pdf': ascii('%PDF-1.7\n1 0 obj\n<< /Type /Catalog >>\nendobj\n'),
    'cut.png': [0x89, ...ascii('PNG\r\n\x1a\n'), 0, 0, 0, 13, ...ascii('IHDR'), 0, 0],
    'cut.jpg': [0xff, 0xd8, 0xff, 0xe1, 0x40, 0, 1, 2, 3],
  };
  const size = {};
  for (const [name, bytes] of Object.entries(files)) {
    writeFileSync(join(dir, name), Buffer.from(bytes));
    size[name] = spawnSync('python3', ['-c', SIZE_SCRIPT, join(dir, name)], { encoding: 'utf8' }).stdout.trim();
  }
  rmSync(dir, { recursive: true });
  assert.deepEqual(size, {
    'shot.png': '1600 1200',
    'base.jpg': '4032 3024',
    'prog.jpg': '4032 3024',
    'anim.gif': '320 240',
    'lossy.webp': '800 600',
    'lossless.webp': '1024 768',
    'extended.webp': '4032 3024',
    'report.pdf': '',
    'cut.png': '',
    'cut.jpg': '',
  });
});

test('the lister keeps every entry when one name is not UTF-8 or a link is dangling', () => {
  const dir = mkdtempSync(join(tmpdir(), 'list-'));
  for (const name of ['ok.txt', 'report.pdf']) writeFileSync(join(dir, name), '');
  writeFileSync(Buffer.concat([Buffer.from(dir + '/caf'), Buffer.from([0xe9]), Buffer.from('.txt')]), '');
  symlinkSync('/nonexistent', join(dir, 'gone.pdf'));
  // The shell runs under a UTF-8 locale, where Python's stdout refuses a name's stray byte; under C it would pass it through.
  const run = spawnSync('python3', ['-c', LIST_SCRIPT, dir], { encoding: 'utf8', env: { ...process.env, LC_ALL: 'en_US.UTF-8' } });
  rmSync(dir, { recursive: true });
  assert.equal(run.status, 0, run.stderr);
  const rows = sortRows(JSON.parse(run.stdout)).map((e) => [e.name, e.dir, e.undecodable]);
  assert.deepEqual(rows, [
    ['caf\uFFFD.txt', false, true],
    ['gone.pdf', false, false],
    ['ok.txt', false, false],
    ['report.pdf', false, false],
  ]);
});
