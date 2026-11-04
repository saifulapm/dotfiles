import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { parseToml } from './toml.mjs';
import { validateTheme, checkTokens } from './theme.mjs';
import { launcherLook, islandLook, osdLook, listLook, marginLook, leaseLook, sendingLook, downloadingLook, chipLook, clockLook, restLook, captureLook, MODES, inOrder } from './voice.mjs';
import { parseQuery } from './launcher.mjs';

const theme = (name) => parseToml(readFileSync(new URL(`../../themes/${name}/theme.toml`, import.meta.url), 'utf8'));
const look = (name) => launcherLook(theme(name));

test('Paper keeps its launcher: an ink cursor row with a red marker, a 34 px serif query and an italic serif detail', () => {
  const p = look('paper');
  assert.deepEqual([p.cursor.fill, p.cursor.marker, p.slot], ['#1C1915', '#C8381E', 'marker']);
  assert.deepEqual([p.query.font, p.query.size], ['Instrument Serif', 34]);
  assert.deepEqual([p.detail.font, p.detail.size, p.detail.italic], ['Instrument Serif', 16, true]);
  assert.deepEqual([p.label.kind, p.label.text('apps'), p.count(3)], ['chip', 'APPS', '3 FOUND']);
});

test("Artboard's launcher follows its board: a search glyph, an Apps pill, icon tiles and a tinted rounded cursor with a return badge", () => {
  const a = look('artboard');
  assert.equal(a.prompt.search, true);
  assert.deepEqual([a.query.font, a.query.size], ['Maple Mono', 20]);
  assert.deepEqual([a.label.kind, a.label.text('apps'), a.label.fill, a.label.color], ['pill', 'Apps', '#EEF1FF', '#3D5AFE']);
  assert.deepEqual([a.slot, a.tile.size, a.tile.fill], ['icon', 32, '#F2F3F6']);
  assert.deepEqual([a.cursor.fill, a.cursor.text, a.cursor.radius, a.cursor.badge], ['#EEF1FF', '#2638C9', 10, '↵']);
  assert.deepEqual([a.name.size, a.name.weight, a.cursor.weight, a.detail.size, a.detail.color], [15, 500, 600, 12, '#57606A']);
  assert.equal(a.count(3), '');
});

const tokensOf = (name) => checkTokens(validateTheme(theme(name)));

test("Frost's launcher field is a nord0 well at 70 % with a #434C5E edge, an accent › and caret, accent Maple Mono keys and a 1 px #ECEFF4 highlight at 6 %", () => {
  const f = launcherLook(tokensOf('frost'));
  assert.deepEqual(f.field, { fill: '#B32E3440', border: '#434C5E', caret: '#88C0D0' });
  assert.deepEqual(f.prompt, { text: '›', color: '#88C0D0', search: false });
  assert.deepEqual(f.chip, { fill: '#434C5E', key: '#88C0D0', font: 'Maple Mono' });
  assert.equal(f.highlight, '#0FECEFF4');
  assert.deepEqual([f.cursor.fill, f.cursor.badge], ['#475666', '↵']);
});

test("Artboard's launcher is what it was beside Frost's: no well, a magnifier, ink keys and no highlight", () => {
  const a = launcherLook(tokensOf('artboard'));
  assert.equal(JSON.stringify(a), '{"voice":"plain","engraved":false,"prompt":{"text":"","color":"#57606A","search":true},"caret":"line","rule":{"color":"#D0D7DE","dashed":false},"small":{"font":"Maple Mono","size":11,"spacing":0,"color":"#57606A"},"tile":{"size":32,"radius":9,"fill":"#F2F3F6"},"query":{"font":"Maple Mono","size":20,"italic":false},"label":{"kind":"pill","fill":"#EEF1FF","color":"#3D5AFE"},"slot":"icon","name":{"font":"Maple Mono","size":15,"weight":500,"spacing":0,"color":"#15171B"},"detail":{"font":"Maple Mono","size":12,"italic":false,"color":"#57606A"},"cursor":{"fill":"#EEF1FF","text":"#2638C9","detail":"#57606A","marker":"transparent","radius":10,"weight":600,"badge":"↵"},"chip":{"fill":"#F2F3F6","key":"#15171B"},"keyChip":{"fill":"#F2F3F6","text":"#57606A","border":0,"borderColor":"transparent","cursorFill":"#FFFFFF","cursorText":"#2638C9","cursorBorder":"transparent","radius":6,"size":11,"spacing":0,"column":0}}');
});

test("Blueprint's launcher follows its board: LAUNCH // <mode>, n MATCHES, a > prompt, numbered uppercase rows and a cyan cursor", () => {
  const b = look('blueprint');
  assert.deepEqual([b.label.kind, b.label.text('apps'), b.count(3)], ['header', 'LAUNCH // APPS', '3 MATCHES']);
  assert.deepEqual([b.prompt.text, b.prompt.color, b.caret], ['>', '#7FE3F0', 'block']);
  assert.deepEqual([b.slot, b.number(0), b.number(7)], ['number', '01', '08']);
  assert.deepEqual([b.title('Font Viewer'), b.detailText('e-book reader')], ['FONT VIEWER', 'E-BOOK READER']);
  assert.deepEqual([b.cursor.fill, b.cursor.text], ['#7FE3F0', '#0A1526']);
});

test('only Blueprint draws its rules dashed', () => {
  assert.deepEqual(['paper', 'artboard', 'blueprint'].map((n) => look(n).rule.dashed), [false, false, true]);
});

test('every mode is named in the theme voice', () => {
  assert.deepEqual(MODES, ['apps', 'windows', 'clipboard', 'emoji', 'calculator', 'commands', 'reminder']);
  assert.equal(look('paper').label.text('clipboard'), 'CLIPBOARD');
  assert.equal(look('artboard').label.text('clipboard'), 'Clipboard');
  assert.equal(look('blueprint').label.text('clipboard'), 'LAUNCH // CLIPBOARD');
  for (const n of ['paper', 'artboard', 'blueprint']) for (const m of MODES) assert.ok(look(n).label.text(m), `${n} ${m}`);
});

test('the apps legend names the five prefixes in each voice, then the moving keys in one short tail', () => {
  const keys = (n) => look(n).legend('apps').keys.map((k) => `${k.key} ${k.word}`);
  assert.deepEqual(keys('paper'), ['W WINDOWS', 'V CLIPBOARD', ': EMOJI', '= CALC', '> COMMANDS']);
  assert.deepEqual(keys('artboard'), ['w windows', 'v clipboard', ': emoji', '= calculator', '> commands']);
  assert.deepEqual(keys('blueprint'), ['[W] WINDOWS', '[V] CLIPBOARD', '[:] EMOJI', '[=] CALC', '[>] COMMANDS']);
  assert.deepEqual(['paper', 'artboard', 'blueprint'].map((n) => look(n).legend('apps').tail), ['J/K · ↵ · ESC', 'j/k · ↵ · esc', 'J/K · ↵ · ESC']);
  assert.equal(look('artboard').legend('apps').chips, true);
  assert.equal(look('blueprint').legend('apps').chips, false);
});

test('inside a mode the legend keeps to the moving keys and drops the prefixes; clipboard adds Shift+Enter copy', () => {
  for (const n of ['paper', 'artboard', 'blueprint']) {
    assert.deepEqual(look(n).legend('emoji').keys, [], n);
    const l = look(n).legend('clipboard');
    assert.match(l.tail, /j\/k.*↵.*esc/i, n);
  }
  const keys = (n) => look(n).legend('clipboard').keys.map((k) => `${k.key} ${k.word}`);
  assert.deepEqual(['paper', 'artboard', 'blueprint'].map(keys), [['⇧↵ COPY'], ['⇧↵ copy'], ['[⇧↵] COPY']]);
});

test('the legend reads as one line for the state and the footer checks', () => {
  assert.equal(look('blueprint').legendLine('apps'), '[W] WINDOWS  [V] CLIPBOARD  [:] EMOJI  [=] CALC  [>] COMMANDS  J/K · ↵ · ESC');
});

test("a row's global key reads Mod+Shift+7 in Artboard, MOD ⇧ 7 in Paper and [MOD ⇧ 7] in Blueprint", () => {
  assert.equal(look('artboard').rowKey('Mod+Shift+7'), 'Mod+Shift+7');
  assert.equal(look('paper').rowKey('Mod+Shift+7'), 'MOD ⇧ 7');
  assert.equal(look('blueprint').rowKey('Mod+Shift+6'), '[MOD ⇧ 6]');
  assert.equal(look('paper').rowKey(undefined), '');
});

test("a row's key chip is a tile in Artboard, an outlined cap in a 96 px column in Paper and bare text in Blueprint", () => {
  const a = look('artboard').keyChip, p = look('paper').keyChip, b = look('blueprint').keyChip;
  assert.deepEqual([a.fill, a.text, a.cursorFill, a.cursorText, a.border, a.radius, a.size], ['#F2F3F6', '#57606A', '#FFFFFF', '#2638C9', 0, 6, 11]);
  assert.deepEqual([p.fill, p.text, p.border, p.borderColor, p.cursorText, p.cursorBorder, p.size, p.column], ['transparent', '#1C1915', 1, '#1C1915', '#FAF6EC', '#FAF6EC', 10, 96]);
  assert.deepEqual([b.fill, b.border, b.text, b.cursorText, b.size], ['transparent', 0, '#80A4C2', '#0A1526', 11]);
});

test('a capture row shows its long detail in Artboard, its tool in Paper, and none in Blueprint', () => {
  const row = { title: 'Annotate region', detail: 'satty on a region of the screen', tool: 'satty' };
  assert.equal(look('artboard').rowDetail(row), 'satty on a region of the screen');
  assert.equal(look('paper').rowDetail(row), 'satty');
  assert.equal(look('blueprint').rowDetail(row), '');
  assert.equal(look('blueprint').rowDetail({ title: 'lock', detail: 'Lock the screen' }), 'LOCK THE SCREEN');
  assert.equal(look('paper').rowDetail({ title: 'lock', detail: 'Lock the screen' }), 'Lock the screen');
});

test('reminder mode reads REMIND, Reminder or LAUNCH // REMINDER, counts what is pending, and heads the pending rows as each board does', () => {
  const p = look('paper'), a = look('artboard'), b = look('blueprint');
  assert.deepEqual([p.label.text('reminder'), a.label.text('reminder'), b.label.text('reminder')], ['REMIND', 'Reminder', 'LAUNCH // REMINDER']);
  assert.deepEqual([p.pendingCount(2), a.pendingCount(2), b.pendingCount(2)], ['2 PENDING', '', '2 PENDING']);
  assert.deepEqual([p.pendingHead(2), a.pendingHead(2), b.pendingHead(2)], [{ text: 'PENDING', right: '' }, { text: 'Pending · 2', right: '' }, { text: 'PENDING', right: '2 OF 50' }]);
  const keys = (l) => l.legend('reminder').keys.map((k) => [k.key, k.word]);
  assert.deepEqual([keys(p), keys(a), keys(b)], [[['↵', 'SET'], ['D', 'DELETE']], [['d', 'delete']], [['[D]', 'DELETE']]]);
  assert.equal(p.legendLine('reminder'), '↵ SET  D DELETE  J/K · ↵ · ESC');
});

test('before the theme loads the launcher still has a whole look', () => {
  const u = launcherLook(null);
  assert.equal(u.label.text('apps'), 'APPS');
  assert.ok(u.cursor.fill && u.query.size);
});

test('each prefix the apps footer names opens its mode', () => {
  const prefixes = look('artboard').legend('apps').keys.map((k) => k.key);
  assert.deepEqual(prefixes.map((p) => parseQuery(p + ' x').mode), ['windows', 'clipboard', 'emoji', 'calculator', 'commands']);
});

test('a name cannot reorder itself with bidi controls, so it draws in the order it is spelt', () => {
  for (const n of ['paper', 'artboard', 'blueprint']) {
    const l = look(n);
    assert.equal(l.title('Zf ‮evil'), n === 'blueprint' ? 'ZF EVIL' : 'Zf evil', n);
    assert.equal(l.detailText('⁧RTLover⁩'), n === 'blueprint' ? 'RTLOVER' : 'RTLover', n);
  }
});

const island = (name) => islandLook(theme(name));
const osd = (name) => osdLook(theme(name));

test("Blueprint's notification reads [ APP ] and T+0S over its summary, uppercase bold in the accent", () => {
  const b = island('blueprint');
  assert.deepEqual([b.appLabel('notify-send'), b.age, b.brackets], ['[ NOTIFY-SEND ]', 'T+0S', true]);
  assert.equal(b.summaryText('Download complete'), 'DOWNLOAD COMPLETE');
  assert.deepEqual([b.summary.font, b.summary.size, b.summary.weight, b.summary.color], ['Maple Mono', 15, 700, '#7FE3F0']);
  assert.deepEqual([b.tile, b.summary.glow, b.glass, b.pad.bottom], [null, '', false, 14]);
});

test("Hi-Fi's notification is a glass display: the app and NOW muted, the summary in bold amber caps with a glow, the body in ink", () => {
  const h = islandLook(checkTokens(validateTheme(theme('hi-fi'))));
  assert.deepEqual([h.appLabel('Chromium'), h.age, h.brackets, h.head.color], ['CHROMIUM', 'NOW', false, '#A89984']);
  assert.equal(h.summaryText('Download complete'), 'DOWNLOAD COMPLETE');
  assert.deepEqual([h.summary.weight, h.summary.color, h.summary.glow, h.body.color], [700, '#FABD2F', '#FABD2F', '#EBDBB2']);
  assert.deepEqual([h.glass, h.pad.bottom], [true, 30]);
});

test("Paper's notification puts the app and NOW in tracked caps over a 24 px serif summary and a 12 px mono body", () => {
  const p = island('paper');
  assert.deepEqual([p.appLabel('Chromium'), p.age, p.head.spacing > 1], ['CHROMIUM', 'NOW', true]);
  assert.deepEqual([p.summary.font, p.summary.size, p.summaryText('Download complete')], ['Instrument Serif', 24, 'Download complete']);
  assert.deepEqual([p.body.font, p.body.size], ['Maple Mono', 12]);
});

test("Artboard's notification has a 40 px rounded tile, the app and now muted, and a 15 px bold summary", () => {
  const a = island('artboard');
  assert.deepEqual([a.tile.size, a.tile.radius, a.tile.fill], [40, 12, '#2B2F36']);
  assert.deepEqual([a.appLabel('Chromium'), a.age], ['Chromium', 'now']);
  assert.deepEqual([a.summary.size, a.summary.weight], [15, 600]);
  assert.deepEqual([a.glyph('chromium'), a.glyph('')], ['C', '•']);
  assert.equal(a.width, 440);
});

const shape = (n) => ({ width: n.width, age: n.age, pad: n.pad, head: n.head, summary: n.summary, body: n.body, tile: n.tile });

test("Frost's notification is a glass card: the app and now muted at 11.5 px, a #ECEFF4 semibold title, a muted body and an accent icon in a 32 px tile of accent at 16 %", () => {
  const f = islandLook(checkTokens(validateTheme(theme('frost'))));
  assert.deepEqual([f.head.size, f.head.color, f.appLabel('Chromium'), f.age], [11.5, '#AEB7C6', 'Chromium', 'now']);
  assert.deepEqual([f.summary.color, f.summary.weight, f.body.color], ['#ECEFF4', 600, '#AEB7C6']);
  assert.deepEqual(f.tile, { size: 32, radius: 9, fill: '#2988C0D0', ink: '#88C0D0' });
});

test("Artboard's notification keeps its look beside Frost's", () => {
  assert.deepEqual(shape(islandLook(checkTokens(validateTheme(theme('artboard'))))), {
    width: 440,
    age: 'now',
    pad: { x: 16, top: 14, bottom: 14 },
    head: { font: 'Maple Mono', size: 12, spacing: 0, color: '#A3A9B4' },
    summary: { font: 'Maple Mono', size: 15, weight: 600, spacing: 0, color: '#FFFFFF' },
    body: { font: 'Maple Mono', size: 13, color: '#C9CED6' },
    tile: { size: 40, radius: 12, fill: '#2B2F36' },
  });
});

test('an empty app name draws no empty brackets and no empty caps', () => {
  for (const n of ['paper', 'artboard', 'blueprint']) assert.equal(island(n).appLabel(''), '', n);
  assert.equal(island('blueprint').appLabel(null), '');
});

test('an app name cannot reorder its label with bidi controls', () => {
  assert.equal(island('blueprint').appLabel('a‮b'), '[ AB ]');
  assert.equal(island('blueprint').appText('a‮b'), 'AB');
});

test('the OSD lights a twentieth for every 5 %, rounded, and clamps', () => {
  const p = osd('paper');
  assert.deepEqual([0, 62, 100, 140, -3].map((v) => p.litCount(v)), [0, 12, 20, 20, 0]);
});

test("Blueprint's OSD reads VOL, ▮ blocks and a three-digit value", () => {
  const b = osd('blueprint');
  assert.deepEqual([b.word('volume'), b.word('brightness'), b.bars, b.valueText(62), b.valueText(5), b.valueText(100)], ['VOL', 'BRT', 'blocks', '062', '005', '100']);
  assert.deepEqual([b.value.weight, b.value.color, b.lit.color, b.unlit.color], [700, '#7FE3F0', '#7FE3F0', '#2E5A72']);
});

test("Paper's OSD reads VOL, 20 accent bars and the value in serif; Artboard's draws a glyph and a rounded #6C83FF bar", () => {
  const p = osd('paper');
  assert.deepEqual([p.word('volume'), p.bars, p.valueText(62), p.value.font, p.lit.color], ['VOL', 'bars', '62', 'Instrument Serif', '#C8381E']);
  const a = osd('artboard');
  assert.deepEqual([a.word('volume'), a.bars, a.valueText(62), a.lit.color, a.unlit.color], ['', 'round', '62', '#6C83FF', '#2B2F36']);
  assert.deepEqual(['paper', 'artboard', 'blueprint'].map((n) => [osd(n).width, osd(n).height]), [[280, 34], [300, 40], [320, 34]]);
});

test("Hi-Fi's volume OSD is a 320 px VU meter whose needle swings from -45 at 0 to +45 at 100 and pins there; brightness keeps the bar", () => {
  const h = osdLook(checkTokens(validateTheme(theme('hi-fi'))));
  assert.deepEqual([h.kind('volume'), h.kind('brightness'), h.meter.width], ['meter', 'bar', 320]);
  assert.deepEqual([62, 100, 120, 0, 95].map((v) => h.meter.angle(v)), [10.8, 45, 45, -45, 40.5]);
  assert.deepEqual([h.meter.valueText(62), h.meter.valueText(120), h.meter.word], ['62', '120', 'VOLUME']);
  // The red zone runs from the 90 mark to the end of the arc, and 95 sits inside it.
  assert.deepEqual([h.meter.red, h.meter.angle(h.meter.red) <= h.meter.angle(95)], [90, true]);
  assert.deepEqual([h.meter.needle.color, h.meter.redColor, h.meter.ticks], ['#FABD2F', '#FB4934', 11]);
});

test('the other themes keep their bar OSD for volume and brightness alike', () => {
  for (const n of ['paper', 'artboard', 'blueprint']) assert.deepEqual([osd(n).kind('volume'), osd(n).kind('brightness'), osd(n).meter], ['bar', 'bar', null], n);
});

test("Frost's volume OSD is a 320 x 52 glass bar: a 6 px #ECEFF4 track at 12 %, an accent fill over 160 ms, the value in #ECEFF4 semibold; brightness keeps the bar", () => {
  const f = osdLook(checkTokens(validateTheme(theme('frost'))));
  assert.deepEqual([f.kind('volume'), f.kind('brightness')], ['track', 'bar']);
  assert.deepEqual([f.track.width, f.track.height, f.track.thickness], [320, 52, 6]);
  assert.deepEqual([f.track.color, f.track.fill, f.track.duration], ['#1FECEFF4', '#88C0D0', 160]);
  assert.deepEqual([f.track.value.color, f.track.value.weight], ['#ECEFF4', 600]);
  assert.deepEqual([f.width, f.height], [300, 40]);
});

test("Artboard's OSD stays its rounded bar for volume and brightness", () => {
  const a = osdLook(checkTokens(validateTheme(theme('artboard'))));
  assert.deepEqual([a.kind('volume'), a.kind('brightness'), a.track, a.width, a.height, a.bars], ['bar', 'bar', null, 300, 40, 'round']);
});

const OCR = { kind: 'ocr', title: 'Text copied', detail: '214 characters', swatch: null };
const COLOUR = { kind: 'colour', title: 'Copied', detail: '#C8381E', swatch: '#C8381E' };
const QR = { kind: 'qr', title: 'QR code copied', detail: '', swatch: null };
const MISS = { kind: 'ocr', title: '', detail: 'No text found', swatch: null };

test("Paper's capture result is the pill: a check, the title in tracked caps, the count in italic serif and a hex in mono", () => {
  const p = captureLook(theme('paper'));
  assert.equal(p.card, false);
  assert.equal(p.titleText(OCR.title), 'TEXT COPIED');
  assert.deepEqual([p.title.font, p.title.size, p.title.spacing], ['Maple Mono', 10, 1.4]);
  assert.deepEqual([p.detail(OCR).font, p.detail(OCR).size, p.detail(OCR).italic], ['Instrument Serif', 17, true]);
  assert.deepEqual([p.detail(COLOUR).font, p.detail(COLOUR).size, p.detail(COLOUR).weight, p.detail(COLOUR).italic], ['Maple Mono', 12, 500, false]);
  assert.deepEqual([p.height, p.pad, p.gap, p.check, p.swatch], [34, 14, 10, 12, 14]);
  // A miss copied nothing: no check, and its words are muted.
  assert.deepEqual([p.detail(MISS).color, p.detail(OCR).color], ['#B9AE99', '']);
  assert.equal(captureLook(null).card, false);
});

test("Artboard's capture result is its notification card from Capture, the result as the summary", () => {
  const a = captureLook(theme('artboard'));
  assert.equal(a.card, true);
  assert.deepEqual(a.note(OCR), { app: 'Capture', summary: 'Text copied · 214 characters', body: 'eng + ben · from region', swatch: null, icon: '', files: [] });
  assert.deepEqual([a.note(COLOUR).summary, a.note(COLOUR).body, a.note(COLOUR).swatch], ['Copied #C8381E', 'colour picked', '#C8381E']);
  assert.deepEqual([a.note(QR).summary, a.note(QR).body], ['QR code copied', 'from region']);
  assert.equal(a.note(MISS).summary, 'No text found');
});

test("Blueprint's capture result is its notification card under [ OCR ] or [ COLOUR ], the count as the body", () => {
  const b = captureLook(theme('blueprint'));
  const n = islandLook(theme('blueprint'));
  assert.equal(b.card, true);
  const ocr = b.note(OCR);
  assert.deepEqual([n.appLabel(ocr.app), n.summaryText(ocr.summary), ocr.body], ['[ OCR ]', 'TEXT COPIED', '214 characters']);
  const colour = b.note(COLOUR);
  assert.deepEqual([n.appLabel(colour.app), n.summaryText(colour.summary), colour.body, colour.swatch], ['[ COLOUR ]', 'COPIED #C8381E', 'colour picked', '#C8381E']);
  assert.deepEqual([n.appLabel(b.note(QR).app), b.note(QR).body], ['[ QR ]', '']);
  assert.deepEqual([n.summaryText(b.note(MISS).summary), b.note(MISS).body], ['NO TEXT FOUND', '']);
});

test('before the theme loads the island still has a whole notification and OSD look', () => {
  assert.equal(islandLook(null).appLabel('x'), 'X');
  assert.equal(osdLook(null).valueText(7), '7');
});

const list = (name) => listLook(theme(name));

test("a list surface's heading is Paper's chip word, Artboard's pill word or Blueprint's NAME // SECTION header", () => {
  assert.deepEqual(['paper', 'artboard', 'blueprint'].map((n) => list(n).heading('control', 'audio')), ['CONTROL', 'Control', 'CONTROL // AUDIO']);
  assert.equal(list('blueprint').heading('notifications', ''), 'NOTIFICATIONS');
});

test("a list surface's current tab takes the launcher's mode label: an ink chip, a tint pill or the cyan cursor", () => {
  assert.deepEqual(['paper', 'artboard', 'blueprint'].map((n) => [list(n).tab.fill, list(n).tab.text, list(n).tab.radius]), [
    ['#1C1915', '#FAF6EC', 0],
    ['#EEF1FF', '#3D5AFE', 8],
    ['#7FE3F0', '#0A1526', 0],
  ]);
  assert.deepEqual(['paper', 'artboard', 'blueprint'].map((n) => list(n).tabText('Wi-Fi')), ['WI-FI', 'Wi-Fi', 'WI-FI']);
});

test("a list surface's legend keys follow the voice: Paper's tracked caps, Artboard's chips, Blueprint's brackets", () => {
  const pairs = [['tab', 'section'], ['j/k', 'move'], ['esc', 'close']];
  assert.deepEqual(list('paper').keys(pairs).map((k) => `${k.key} ${k.word}`), ['TAB SECTION', 'J/K MOVE', 'ESC CLOSE']);
  assert.deepEqual(list('artboard').keys(pairs).map((k) => `${k.key} ${k.word}`), ['tab section', 'j/k move', 'esc close']);
  assert.deepEqual(list('blueprint').keys(pairs).map((k) => `${k.key} ${k.word}`), ['[TAB] SECTION', '[J/K] MOVE', '[ESC] CLOSE']);
  assert.equal(list('paper').small.spacing > 1, true);
  assert.equal(list('blueprint').keyText('Mod ⇧ t'), '[MOD ⇧ T]');
  assert.equal(list('paper').keyText('Mod ⇧ t'), 'MOD ⇧ T');
  assert.equal(list('artboard').keyText('Mod ⇧ t'), 'Mod ⇧ t');
});

test("a list surface keeps the launcher's cursor row and rules", () => {
  for (const n of ['paper', 'artboard', 'blueprint']) {
    assert.deepEqual(list(n).cursor, look(n).cursor, n);
    assert.deepEqual(list(n).rule, look(n).rule, n);
  }
});

test("a list surface writes an entry's age in whole units, floored: NOW, now or T+0S under a minute, then minutes, hours and days", () => {
  const S = 1000, M = 60 * S, H = 60 * M, D = 24 * H;
  const ages = [0, 59 * S, 60 * S, 5 * M, 59 * M, 60 * M, 3 * H, 23 * H + 59 * M, 24 * H, 2 * D + 5 * H];
  assert.deepEqual(ages.map((ms) => list('paper').ageText(ms)), ['NOW', 'NOW', '1M', '5M', '59M', '1H', '3H', '23H', '1D', '2D']);
  assert.deepEqual(ages.map((ms) => list('artboard').ageText(ms)), ['now', 'now', '1m', '5m', '59m', '1h', '3h', '23h', '1d', '2d']);
  assert.deepEqual(ages.map((ms) => list('blueprint').ageText(ms)), ['T+0S', 'T+0S', 'T+1M', 'T+5M', 'T+59M', 'T+1H', 'T+3H', 'T+23H', 'T+1D', 'T+2D']);
  // Hi-Fi says NOW, as its island does, with no mission clock.
  assert.deepEqual(ages.map((ms) => listLook(checkTokens(validateTheme(theme('hi-fi')))).ageText(ms)), ['NOW', 'NOW', '1M', '5M', '59M', '1H', '3H', '23H', '1D', '2D']);
});

const margin = (name) => marginLook(theme(name));
const foot = { idx: 2, app: 'foot', title: '~' };
// Sunday 18 October 2026, local time.
const SUN = new Date(2026, 9, 18, 9, 30);
const right = { sync: '', goal: { title: 'Ship v2', left: '3d' }, wifi: 'wifi', battery: '82%' };

test('the top-left margin reads each board: 02 — FOOT · ~, Page 02 / foot — ~ and [02] FOOT — ~', () => {
  assert.deepEqual(['paper', 'artboard', 'blueprint'].map((n) => margin(n).drawn(foot, SUN, right).left), ['02 — FOOT · ~', 'Page 02 / foot — ~', '[02] FOOT — ~']);
});

test('an empty workspace reads only its number', () => {
  const empty = { idx: 4, app: null, title: null };
  assert.deepEqual(['paper', 'artboard', 'blueprint'].map((n) => margin(n).drawn(empty, SUN, right).left), ['04', 'Page 04', '[04]']);
});

test('on 2026-10-18 the date reads SUN 18 OCT, Sun 18 Oct and 2026-10-18', () => {
  assert.deepEqual(['paper', 'artboard', 'blueprint'].map((n) => margin(n).date(SUN)), ['SUN 18 OCT', 'Sun 18 Oct', '2026-10-18']);
  assert.equal(margin('blueprint').date(new Date(2026, 0, 5)), '2026-01-05');
});

test('the top-right margin reads each board, with its own separators and goal countdown', () => {
  assert.equal(margin('paper').drawn(foot, SUN, right).right, 'SHIP V2 · 3D — WIFI — 82% — SUN 18 OCT');
  assert.equal(margin('artboard').drawn(foot, SUN, right).right, 'Ship v2 · 3d Wi-Fi 82% Sun 18 Oct');
  assert.equal(margin('blueprint').drawn(foot, SUN, right).right, 'SHIP V2 T−3D · WIFI · 82% · 2026-10-18');
});

test("the goal takes each board's colour and weight, and Artboard's accent dot", () => {
  assert.deepEqual(['paper', 'artboard', 'blueprint'].map((n) => [margin(n).goalColor, margin(n).dot]), [
    ['#C8381E', false],
    ['#15171B', true],
    ['#FFB547', false],
  ]);
  assert.deepEqual([margin('blueprint').goal({ title: 'Read', left: null }), margin('blueprint').goal({ title: 'Ship', left: 'late' }), margin('paper').goal(null)], ['READ', 'SHIP LATE', '']);
});

test('the workspace number takes the board colour: ink in Paper and Artboard, the accent in Blueprint', () => {
  assert.deepEqual(['paper', 'artboard', 'blueprint'].map((n) => [margin(n).numberColor, margin(n).number(3)]), [
    ['#1C1915', '03'],
    ['#15171B', 'Page 03'],
    ['#7FE3F0', '[03]'],
  ]);
});

test('Artboard spells Wi-Fi as its board does, and a sync failure leads the right margin in every voice', () => {
  assert.deepEqual([margin('artboard').word('no wifi'), margin('paper').word('no wifi')], ['No Wi-Fi', 'NO WIFI']);
  assert.equal(margin('blueprint').drawn(foot, SUN, { ...right, sync: 'sync !' }).right.slice(0, 9), 'SYNC ! · ');
});

test('unread mail reads MAIL 3, mail 3 and MAIL 3 between the goal and Wi-Fi, in each board colour and weight', () => {
  const mail = { ...right, mail: 3 };
  assert.deepEqual(['paper', 'artboard', 'blueprint'].map((n) => margin(n).drawn(foot, SUN, mail).right), [
    'SHIP V2 · 3D — MAIL 3 — WIFI — 82% — SUN 18 OCT',
    'Ship v2 · 3d mail 3 Wi-Fi 82% Sun 18 Oct',
    'SHIP V2 T−3D · MAIL 3 · WIFI · 82% · 2026-10-18',
  ]);
  assert.deepEqual(['paper', 'artboard', 'blueprint'].map((n) => [margin(n).mail(3), margin(n).mailColor, margin(n).mailWeight]), [
    ['MAIL 3', '#1C1915', 700],
    ['mail 3', '#15171B', 500],
    ['MAIL 3', '#7FE3F0', 400],
  ]);
  assert.equal(margin('paper').drawn(foot, SUN, { ...right, mail: 0 }).right, 'SHIP V2 · 3D — WIFI — 82% — SUN 18 OCT');
});

// The shell reads Hi-Fi through checkTokens, as the bracket voice plus engraved.
const hifiMargin = () => marginLook(checkTokens(validateTheme(theme('hi-fi'))));

test("Hi-Fi's bar lights one amber lamp before the shown workspace's number, 01 in amber, as the other themes show only the current one", () => {
  const ws = [1, 2, 3, 4, 5, 6, 7, 8, 9].map((idx) => ({ idx, active: idx === 2, urgent: idx === 2 || idx === 5 }));
  assert.deepEqual(hifiMargin().lamps(ws), [{ idx: 2, text: '02', light: 'lit', color: '#FABD2F' }]);
  assert.deepEqual(hifiMargin().lamps([]), []);
});

test("Hi-Fi marks an urgent workspace after the title as a red lamp and its muted number, at most 3, then a count", () => {
  const h = hifiMargin();
  assert.deepEqual(h.marks([5, 7]), [
    { text: '05', color: '#A89984', lamp: 'red' },
    { text: '07', color: '#A89984', lamp: 'red' },
  ]);
  assert.deepEqual(h.marks([2, 3, 5, 7, 9]).map((m) => [m.text, m.lamp]), [['02', 'red'], ['03', 'red'], ['05', 'red'], ['+2', '']]);
  assert.deepEqual(h.marks([]), []);
});

test("Hi-Fi's resting clock is lit amber with a glow on its glass; the other themes keep the island's own text colour", () => {
  assert.deepEqual(restLook(checkTokens(validateTheme(theme('hi-fi')))), { color: '#FABD2F', glow: '#FABD2F' });
  for (const n of ['paper', 'artboard', 'blueprint']) assert.deepEqual(restLook(checkTokens(validateTheme(theme(n)))), { color: '', glow: '' }, n);
});

test("Frost's bar sets the workspace as 2 in accent semibold, the app in ink and the path in muted, a danger dot before an ink goal, and an ink date at 12.5 px", () => {
  const f = margin('frost');
  assert.deepEqual([f.number(2), f.numberColor, f.numberWeight, f.size, f.chip], ['2', '#88C0D0', 600, 12.5, true]);
  assert.equal(f.drawn(foot, SUN, right).left, '2  foot  ~');
  assert.deepEqual([f.tail(foot), f.tailColor, f.path(foot)], ['  foot', '#D8DEE9', '  ~']);
  assert.deepEqual([f.dot, f.dotColor, f.goalColor, f.dateColor], [true, '#BF616A', '#D8DEE9', '#D8DEE9']);
  assert.equal(f.drawn(foot, SUN, right).right, 'Ship v2 · 3d Wi-Fi 82% Sun 18 Oct');
});

test("Artboard's bar keeps Page 02, its muted tail, accent dot and muted date, with no size of its own", () => {
  const a = margin('artboard');
  assert.deepEqual([a.number(2), a.numberColor, a.tailColor, a.path(foot), a.dotColor, a.dateColor, a.size], ['Page 02', '#15171B', '#57606A', '', '#3D5AFE', '#57606A', undefined]);
  assert.equal(a.chip, false);
});

test("Hi-Fi's bar reads the app in ink and the path in muted caps, the goal in ink after a red lamp, and the date as SUN 1 NOV", () => {
  const h = hifiMargin();
  assert.deepEqual([h.tail(foot), h.tailColor, h.path(foot), h.path({ idx: 4, app: null, title: null })], ['  FOOT', '#EBDBB2', '  ~', '']);
  assert.deepEqual([h.goal(right.goal), h.goalColor, h.goalLamp], ['SHIP V2 · 3D', '#EBDBB2', 'red']);
  assert.deepEqual([h.date(new Date(2026, 10, 1)), h.dateColor], ['SUN 1 NOV', '#EBDBB2']);
});

test("Blueprint's margins draw no lamps, path or goal lamp and keep the muted date", () => {
  const b = margin('blueprint');
  assert.deepEqual(b.lamps([{ idx: 1, active: true, urgent: false }]), []);
  assert.deepEqual([b.path(foot), b.goalLamp, b.dateColor, b.tailColor, b.drawn(foot, SUN, right).left], ['', '', '#80A4C2', '#80A4C2', '[02] FOOT — ~']);
});

test('a bidi control in a window title cannot reorder the margin', () => {
  assert.equal(margin('blueprint').drawn({ idx: 1, app: 'foot', title: 'a‮b' }, SUN, right).left, '[01] FOOT — AB');
});

test("a newline in a notification's app or summary keeps each to one line, and the body cannot reorder itself", () => {
  const b = island('blueprint');
  assert.equal(b.appLabel('two\nlines'), '[ TWO LINES ]');
  assert.equal(b.summaryText('Download\ncomplete'), 'DOWNLOAD COMPLETE');
  assert.equal(island('paper').summaryText('a\r\n\tb'), 'a b');
  for (const n of ['paper', 'artboard', 'blueprint']) assert.equal(island(n).bodyText('x‮yz\nnext'), 'xyz\nnext', n);
});

test("the notification centre's group head names the app on one line and its count, or the count alone", () => {
  assert.deepEqual(['paper', 'artboard', 'blueprint'].map((n) => list(n).groupHead('Fire\nfox', 3)), ['FIRE FOX · 3', 'Fire fox · 3', 'FIRE FOX · 3']);
  assert.deepEqual(['paper', 'artboard', 'blueprint'].map((n) => list(n).groupHead('', 1)), ['1', '1', '1']);
});

test('a polkit request cannot reorder what it asks with bidi controls, and keeps its lines', () => {
  assert.equal(inOrder('run ‮evil.sh as root'), 'run evil.sh as root');
  assert.equal(inOrder('a⁦b⁩\nc‪‬d'), 'ab\ncd');
  assert.equal(inOrder(undefined), '');
});

test('a notification cannot draw control characters: BEL and ESC drop out of its app, title and body, and the body keeps its lines and tabs', () => {
  for (const n of ['paper', 'artboard', 'blueprint', 'frost', 'hi-fi']) {
    const l = islandLook(checkTokens(validateTheme(theme(n))));
    assert.equal(l.summaryText('A\u0007\u001b[31mred').toLowerCase(), 'a[31mred', n);
    assert.equal(l.appText('Chro\u001bmium\u009b').toLowerCase(), 'chromium', n);
    assert.equal(l.bodyText('one\u0000two\nthree\tfour\u007f'), 'onetwo\nthree\tfour', n);
  }
});

// The lease slot and card as the m21 boards draw them (XX2P8V57): project/AgentLease*.dc.html and Lease*.dc.html.
const lease = (name) => leaseLook(theme(name));
const slotText = (l, who, left) => [l.slot.label.text, l.slot.who.text(who), l.time(left)].filter((x) => x).join(' ');

test("each slot reads its board's words at its board's width, the time left as m:ss at the right", () => {
  assert.equal(slotText(lease('paper'), 'claude', 872000), 'AGENT CLAUDE 14:32');
  assert.equal(slotText(lease('artboard'), 'claude', 872000), 'Agent · claude 14:32');
  assert.equal(slotText(lease('blueprint'), 'claude', 872000), '[ AGENT ] CLAUDE T−14:32');
  assert.deepEqual(['paper', 'artboard', 'blueprint'].map((t) => [lease(t).slot.width, lease(t).slot.height]), [[300, 34], [264, 40], [320, 34]]);
  assert.deepEqual([lease('paper').time(42000), lease('blueprint').time(42000), lease('paper').time(7200000)], ['0:42', 'T−0:42', '120:00']);
});

test("Paper's slot: a red square, AGENT in the island's head colour and a 20 px serif time", () => {
  const s = lease('paper').slot;
  assert.deepEqual([s.mark.shape, s.mark.size, s.mark.color], ['square', 8, '#C8381E']);
  assert.deepEqual([s.label.size, s.label.color, s.who.weight, s.time.font, s.time.size], [10, '#D9CFBB', 500, 'Instrument Serif', 20]);
});

test("Artboard's slot: a #6C83FF dot, Agent · claude in its body colour and the time in white", () => {
  const s = lease('artboard').slot;
  assert.deepEqual([s.mark.shape, s.mark.color, s.label.text, s.who.color, s.who.size, s.time.color], ['dot', '#6C83FF', '', '#C9CED6', 13, '#FFFFFF']);
});

test("Artboard's card is a selected frame: an accent outline, white handles, its Island label and white type", () => {
  const a = lease('artboard').card;
  assert.deepEqual([a.box.frame, a.box.handles, a.box.handleFill, a.label, a.ink], [{ width: 1.5, color: '#3D5AFE' }, true, '#FFFFFF', 'Island', '#FFFFFF']);
  assert.deepEqual([lease('paper').card.label, lease('blueprint').card.label], ['', '']);
});

test("Blueprint's slot: [ AGENT ] muted, the name bold in ink, the time bold in cyan", () => {
  const s = lease('blueprint').slot;
  assert.deepEqual([s.mark, s.label.color, s.who.color, s.who.weight, s.time.color, s.time.weight], [null, '#80A4C2', '#D6F4F8', 700, '#7FE3F0', 700]);
});

test("the last minute: Paper's surface sheet with a vermilion rule, Artboard's #B4380B chip and ringed dot, Blueprint's amber frame and glow", () => {
  const p = lease('paper').warning;
  assert.deepEqual([p.box.fill, p.box.text, p.box.frame.width, p.box.frame.color, p.label, p.time], ['#FAF6EC', '#1C1915', 1.5, '#C8381E', '#575653', '#C8381E']);
  const a = lease('artboard').warning;
  assert.deepEqual([a.box, a.time, a.chip, a.ring], [null, '#B4380B', '#FFF1E8', '#FFF1E8']);
  const b = lease('blueprint').warning;
  assert.deepEqual([b.box.frame.color, b.box.glow, b.time], ['#FFB547', '#FFB547', '#FFB547']);
});

test("each card follows its board: Paper's serif name and LEFT, Artboard's tile and chips, Blueprint's rows", () => {
  const p = lease('paper').card;
  assert.deepEqual([p.layout, p.width, p.who('claude'), p.unlocked('14:05'), p.keys], ['print', 420, 'claude', 'unlocked 14:05', [['↵', 'LOCK NOW'], ['ESC', 'CLOSE']]]);
  const a = lease('artboard').card;
  assert.deepEqual([a.layout, a.width, a.head, a.who('claude'), a.unlocked('14:05'), a.bar, a.keys], ['card', 440, 'Agent · lease', 'claude', 'unlocked 14:05', 'round', [['↵', 'lock now'], ['esc', 'close']]]);
  const b = lease('blueprint').card;
  assert.deepEqual([b.layout, b.width, b.title('claude'), b.who('claude'), b.unlocked('14:05'), b.bar, b.keys], ['sheet', 420, 'CLAUDE HAS THE SESSION', 'CLAUDE', 'UNLOCKED 14:05', 'blocks', [['[↵]', 'LOCK NOW'], ['[ESC]', 'CLOSE']]]);
});

test('a holder any caller names is one line without bidi controls, in the slot and the card', () => {
  assert.equal(lease('paper').slot.who.text('cl\naude\u202e x'), 'CL AUDE X');
  assert.equal(lease('artboard').slot.who.text('\u202eclaude'), 'Agent · claude');
  assert.equal(lease('blueprint').card.title('a\nb'), 'A B HAS THE SESSION');
});

const sending = (name) => sendingLook(theme(name));
const words = (l, count, to, pct) => l.parts.map((p) => p.text(count, to, pct)).join(' ');

test("Paper's sending slot: 300 by 34, a red square, SENDING 2 FILES TO NUC · in the island's text, a 20 px serif percent and a 4 px red bar on paper", () => {
  const s = sending('paper');
  assert.deepEqual([s.width, s.height, s.pad, s.gap], [300, 34, 14, 10]);
  assert.deepEqual([s.mark.shape, s.mark.size, s.mark.color], ['square', 8, '#C8381E']);
  assert.deepEqual([words(s, 2, 'nuc', 48), words(s, 1, 'n\u202eu\nc', 0), s.parts[0].size, s.parts[0].color], ['SENDING 2 FILES TO NUC ·', 'SENDING 1 FILE TO NU C ·', 10, '']);
  assert.deepEqual([s.pct.text(48), s.pct.font, s.pct.size], ['48%', 'Instrument Serif', 20]);
  assert.deepEqual([s.bar.at, s.bar.height, s.bar.track, s.bar.fill], ['bottom', 4, '#F1E9D8', '#C8381E']);
});

test("Artboard's sending slot: a 380 by 40 pill, an upload glyph, the percent in its words and a 6 px rounded bar after them", () => {
  const s = sending('artboard');
  assert.deepEqual([s.width, s.height, s.pad, s.gap, s.mark.shape, s.mark.size], [380, 40, 16, 10, 'upload', 16]);
  assert.deepEqual([words(s, 2, 'nuc', 48), s.parts[0].size, s.parts[0].weight, s.pct], ['Sending 2 files to nuc · 48%', 13, 500, null]);
  assert.deepEqual([s.bar.at, s.bar.height, s.bar.radius, s.bar.track, s.bar.fill], ['inline', 6, 3, '#2B2F36', '#6C83FF']);
});

test("Blueprint's sending slot: 420 by 34, [ TAILDROP ] → NUC 2 FILES in mono, a cyan percent and a 3 px cyan bar on the line colour", () => {
  const s = sending('blueprint');
  assert.deepEqual([s.width, s.height, s.mark], [420, 34, null]);
  assert.equal(words(s, 2, 'nuc', 48), '[ TAILDROP ] → NUC 2 FILES');
  assert.deepEqual(s.parts.map((p) => [p.size, p.color, p.weight]), [[12, '#80A4C2', 400], [12, '#D6F4F8', 700], [10, '#80A4C2', 400]]);
  assert.deepEqual([s.pct.text(48), s.pct.color, s.bar.at, s.bar.height, s.bar.track, s.bar.fill], ['48%', '#7FE3F0', 'bottom', 3, '#2E5A72', '#7FE3F0']);
});

test('one part of each slot names the machine, and only that one elides', () => {
  for (const t of ['paper', 'artboard', 'blueprint']) assert.equal(sending(t).parts.filter((p) => p.name).length, 1, t);
});

const downloading = (name) => downloadingLook(theme(name));

test("Paper's downloading slot: 480 by 46, a 12 px line over a 4 px accent bar on #4A4338, a red square before a failure", () => {
  const d = downloading('paper');
  assert.deepEqual([d.width, d.height, d.pad, d.head, d.tile, d.chip], [480, 46, 16, null, null, null]);
  assert.deepEqual([d.line.size, d.line.weight, d.line.color], [12, 400, '']);
  assert.deepEqual([d.bar.height, d.bar.radius, d.bar.track, d.bar.fill], [4, 0, '#4A4338', '#C8381E']);
  assert.deepEqual([d.failure.mark, d.failure.color, d.failure.box], [{ shape: 'square', size: 8, color: '#C8381E' }, '', null]);
});

test("Artboard's downloading slot: 440 wide with a 40 px play tile, YouTube and the folder at 12 px, a 15 px bold line, a 4 px rounded bar and a failed chip", () => {
  const d = downloading('artboard');
  assert.deepEqual([d.width, d.height, d.tile.size, d.tile.radius, d.tile.fill], [440, 76, 40, 12, '#2B2F36']);
  assert.deepEqual([d.head.left, d.head.right('audio', '14:32'), d.head.right('video', '14:32'), d.head.right('', '14:32'), d.head.size], ['YouTube', '~/Music/YouTube', '~/Videos/YouTube', '', 12]);
  assert.deepEqual([d.line.size, d.line.weight], [15, 700]);
  assert.deepEqual([d.bar.height, d.bar.radius, d.bar.track, d.bar.fill], [4, 2, '#2B2F36', '#6C83FF']);
  assert.deepEqual(d.chip, { fill: '#FFF1E8', color: '#B4380B', radius: 8, padX: 8, padY: 2 });
});

test("Blueprint's downloading slot: 420 wide, [ YOUTUBE ] and the clock at 10 px, a 14 px bold accent line, a 3 px bar on the line colour and an amber failure frame", () => {
  const d = downloading('blueprint');
  assert.deepEqual([d.width, d.height, d.tile], [420, 70, null]);
  assert.deepEqual([d.head.left, d.head.right('audio', '14:32'), d.head.size, d.head.color], ['[ YOUTUBE ]', '14:32', 10, '#80A4C2']);
  assert.deepEqual([d.line.size, d.line.weight, d.line.color], [14, 700, '#7FE3F0']);
  assert.deepEqual([d.bar.height, d.bar.track, d.bar.fill], [3, '#2E5A72', '#7FE3F0']);
  assert.deepEqual([d.failure.color, d.failure.box], ['#FFB547', { frame: { width: 1, color: '#FFB547' }, glow: '#FFB547' }]);
});

const chip = (name) => chipLook(theme(name));

test("Paper's file chip: a surface tag with a grip, a file glyph and tracked caps, framed in ink on a row; dragged, a dashed paper slot and a 1.5 px red frame", () => {
  const p = chip('paper');
  assert.deepEqual([p.font, p.size, p.spacing, p.gap, p.cut, p.toastPlace, p.rowPlace], ['Maple Mono', 10, 1.4, 7, 0, 'body', 'beforeAge']);
  assert.deepEqual([p.toast.fill, p.toast.frame, p.toast.text, p.toast.pad, p.toast.radius], ['#FAF6EC', '#FAF6EC', '#1C1915', [3, 9, 3, 7], 0]);
  assert.deepEqual([p.row.fill, p.row.frame, p.cursor.frame], ['#FAF6EC', '#1C1915', '#FAF6EC']);
  assert.deepEqual([p.grip, p.glyph], [{ w: 8, h: 12, r: 1.1 }, { w: 12, h: 14, stroke: 1.2, path: 'M1.5 1.5h6l3 3v8h-9z M7.5 1.5v3h3' }]);
  assert.deepEqual([p.empty.color, p.empty.width, p.empty.content], ['#F1E9D8', 1, true]);
  assert.deepEqual([p.frame.width, p.frame.color, p.dragAge], [1.5, '#C8381E', '']);
  const d = p.drag;
  assert.deepEqual([d.fill, d.frame, d.frameWidth, d.text, d.shadow, d.pad, d.gap, d.size, d.weight], ['#FAF6EC', '#1C1915', 1, '#1C1915', '#1C1915', [6, 12, 6, 9], 9, 12, 500]);
});

test("Artboard's file chip: a rounded tile-coloured pill beside the card and after a row's age; dragged, a dashed blue slot and a white pill named in ink", () => {
  const a = chip('artboard');
  assert.deepEqual([a.size, a.spacing, a.gap, a.toastPlace, a.rowPlace], [11, 0, 6, 'column', 'afterAge']);
  assert.deepEqual([a.toast.fill, a.toast.text, a.toast.grip, a.toast.glyph, a.toast.pad, a.toast.radius], ['#2B2F36', '#C9CED6', '#A3A9B4', '#FFFFFF', [8, 10, 8, 10], 10]);
  assert.deepEqual([a.row.fill, a.row.text, a.row.grip, a.row.pad, a.row.radius, a.cursor.fill], ['#F2F3F6', '#57606A', '#8A909B', [5, 8, 5, 8], 8, '#FFFFFF']);
  assert.deepEqual([a.grip, a.glyph], [{ w: 8, h: 12, r: 1 }, { w: 14, h: 14, stroke: 1.3, path: 'M3 1.5h5l3 3v8H3z M8 1.5v3h3' }]);
  assert.deepEqual([a.empty.color, a.empty.width, a.empty.content, a.frame], ['#6C83FF', 1.5, false, null]);
  const d = a.drag;
  assert.deepEqual([d.fill, d.frame, d.frameWidth, d.text, d.grip, d.glyph, d.radius, d.size, d.weight], ['#FFFFFF', '#3D5AFE', 1.5, '#15171B', null, '#2638C9', 10, 12, 500]);
});

test("Blueprint's file chip: a cut-corner cyan frame under a row's age, inverted on the cursor row; dragged, a dashed muted slot and DRAGGING for the age", () => {
  const b = chip('blueprint');
  assert.deepEqual([b.font, b.size, b.spacing, b.gap, b.cut, b.toastPlace, b.rowPlace], ['Maple Mono', 10, 1.2, 6, 7, 'body', 'underAge']);
  assert.deepEqual([b.toast.fill, b.toast.frame, b.toast.text, b.toast.grip, b.toast.pad], ['#0A1526', '#7FE3F0', '#7FE3F0', '#80A4C2', [3, 10, 3, 6]]);
  assert.deepEqual([b.cursor.fill, b.cursor.frame, b.cursor.text, b.cursor.grip], ['#7FE3F0', '#0A1526', '#0A1526', '#0A1526']);
  assert.deepEqual([b.grip, b.glyph], [{ w: 6, h: 10, r: 1 }, { w: 9, h: 11, stroke: 1, path: 'M.5 .5h5l3 3v7h-8z' }]);
  assert.deepEqual([b.empty.color, b.empty.content, b.frame, b.dragAge], ['#80A4C2', false, null, 'DRAGGING']);
  assert.deepEqual([b.drag.frame, b.drag.text, b.drag.cut, b.drag.pad, b.drag.spacing], ['#7FE3F0', '#D6F4F8', 9, [6, 14, 6, 9], 0.72]);
});

test("a chip reads the file's extension or the count, and the drag image names the file in one line without controls", () => {
  const p = chip('paper');
  assert.deepEqual([p.label(['/d/IMG_2041.heic']), p.label(['/d/a', '/d/b', '/d/c'])], ['HEIC', '3 FILES']);
  assert.equal(p.name(['/d/IMG_2041.HEIC']), 'IMG_2041.HEIC');
  assert.equal(p.name(['/d/a\nb‮\u0007c.jpg']), 'a bc.jpg');
  assert.equal(p.name(['/d/a', '/d/b']), '2 FILES');
  assert.equal(p.label(['/d/x.he‮ic']), 'HEIC');
});

const clock = (name) => clockLook(theme(name));

test("Paper's world clock: a WORLD CLOCK head, a serif Dhaka with a HOME chip at 34 px, and each offset beside its city", () => {
  const p = clock('paper');
  assert.deepEqual([p.gridWidth, p.gap, p.head, p.city('Dhaka'), p.mark], [238, 20, 'WORLD CLOCK', 'Dhaka', { text: 'HOME', boxed: true }]);
  assert.deepEqual([p.homeTime.font, p.homeTime.size, p.time.size, p.name.size, p.offset.size, p.offset.spacing], ['Instrument Serif', 34, 28, 20, 10, 1.4]);
  assert.deepEqual([p.place, p.city('New York'), p.offsetText('−10h'), p.dayText('tomorrow'), p.rule.dashed], ['name', 'New York', '−10h', 'TOMORROW', false]);
});

test("Artboard's world clock: Dhaka · home over a bold 26 px time, the offset under each city and #2B2F36 rules", () => {
  const a = clock('artboard');
  assert.deepEqual([a.gridWidth, a.gap, a.head, a.city('Dhaka') + a.mark.text, a.mark.boxed], [224, 22, '', 'Dhaka · home', false]);
  assert.deepEqual([a.homeTime.size, a.homeTime.weight, a.time.size, a.time.weight, a.name.size, a.name.weight], [26, 700, 17, 700, 14, 500]);
  assert.deepEqual([a.place, a.offset.size, a.offset.color, a.rule.color, a.rule.dashed, a.dayText('yesterday')], ['under', 12, '#A3A9B4', '#2B2F36', false, 'yesterday']);
});

test("Blueprint's world clock: uppercase cities, a cyan home time, the offset at the right as −10H and dashed rules", () => {
  const b = clock('blueprint');
  assert.deepEqual([b.gridWidth, b.gap, b.head, b.city('Dhaka') + b.mark.text, b.mark.boxed], [224, 20, '', 'DHAKA · HOME', false]);
  assert.deepEqual([b.homeTime.size, b.homeTime.color, b.time.size, b.time.color, b.name.size, b.name.color], [15, '#7FE3F0', 15, '#D6F4F8', 10, '#80A4C2']);
  assert.deepEqual([b.place, b.city('New York'), b.offsetText('−10h'), b.offsetWidth, b.rule.color, b.rule.dashed], ['right', 'NEW YORK', '−10H', 34, '#2E5A72', true]);
});

test("Paper's month grid: a CALENDAR head, a split serif title, Monday weeks in 34 px cells and a boxed today", () => {
  const g = clock('paper').grid;
  assert.deepEqual([g.head, g.header, g.weekStart, g.weekdays.join(''), g.cell, g.rowHeight, g.weekHeight], ['CALENDAR', '', 1, 'MTWTFSS', 34, 26, 26]);
  assert.deepEqual(g.title.parts({ month: 'October', abbr: 'Oct', year: 2026 }), ['October', '2026']);
  assert.deepEqual([g.title.place, g.title.left.font, g.title.left.size, g.title.right.italic, g.title.right.size], ['split', 'Instrument Serif', 24, true, 16]);
  assert.deepEqual([g.weekday.size, g.weekday.spacing, g.day.size, g.today.w, g.today.h, g.today.inverted, g.today.borderColor, g.today.border], [10, 1, 12, 26, 22, false, '#C8381E', 1.5]);
});

test("Artboard's month grid: no head, October 2026 at 15 px, Sunday weeks, #A3A9B4 weekdays and a white pill for today", () => {
  const g = clock('artboard').grid;
  assert.deepEqual([g.head, g.header, g.weekStart, g.weekdays.join(' '), g.cell, g.rowHeight, g.weekHeight], ['', '', 0, 'Su Mo Tu We Th Fr Sa', 32, 28, 28]);
  assert.deepEqual(g.title.parts({ month: 'October', abbr: 'Oct', year: 2026 }), ['October 2026']);
  assert.deepEqual([g.title.place, g.title.left.size, g.title.left.weight, g.weekday.size, g.weekday.color, g.day.color], ['line', 15, 500, 11, '#A3A9B4', '#C9CED6']);
  assert.deepEqual([g.today.w, g.today.h, g.today.radius, g.today.inverted, g.today.border], [28, 24, 8, true, 0]);
});

test("Blueprint's month grid: [ CALENDAR ] and OCT 2026 across the card, Monday weeks, a 22 px weekday line and a cyan today cell", () => {
  const g = clock('blueprint').grid;
  assert.deepEqual([g.head, g.header, g.weekStart, g.weekdays.join(''), g.cell, g.rowHeight, g.weekHeight], ['', '[ CALENDAR ]', 1, 'MTWTFSS', 32, 26, 22]);
  assert.deepEqual(g.title.parts({ month: 'October', abbr: 'Oct', year: 2026 }), ['OCT 2026']);
  assert.deepEqual([g.title.place, g.title.left.size, g.title.left.color, g.weekday.size, g.weekday.color, g.rowGap], ['header', 10, '#80A4C2', 10, '#80A4C2', 2]);
  assert.deepEqual([g.today.w, g.today.h, g.today.inverted, g.today.fill, g.today.border], [32, 26, true, '#7FE3F0', 0]);
});

// A window's title is its file's name, which anyone who sends a file controls: a newline stacked a second line under the margin rule, and ESC or BEL drew tofu.
test('the margin draws a window title on one line, with no control characters or bidi marks', () => {
  for (const name of ['paper', 'artboard', 'blueprint']) {
    for (const title of ['line1\nline2 INJECT.pdf', 'esc\u001b[31mred\u001b]0;pwn\u0007.pdf', 'a\u0085b\u009bc', 'rtl‮fdp.exe', 'mark‎‏؜s']) {
      const tail = margin(name).tail({ idx: 1, app: 'org.pwmt\u0007zathura\n', title });
      assert.doesNotMatch(tail, /[\u0000-\u001f\u007f-\u009f‎‏؜‪-‮⁦-⁩]/, `${name}: ${JSON.stringify(tail)}`);
    }
    assert.match(margin(name).tail({ idx: 1, app: 'zathura', title: 'line1\nline2 INJECT.pdf' }), /line1 line2 INJECT\.pdf/i);
  }
});

// The marks as drawn: each segment's text joined, without the gap that sets them off from the title.
const marks = (name, idxs) => margin(name).marks(idxs).map((s) => s.text).join('').trim();

test("the focused column reads 2 / 3 after the workspace number, [2 / 3] in Blueprint's brackets", () => {
  assert.deepEqual(['paper', 'artboard', 'blueprint'].map((n) => margin(n).column({ at: 2, of: 3 })), ['  2 / 3', '  2 / 3', ' [2 / 3]']);
});

test('a lone column or no tiled window draws no column', () => {
  assert.deepEqual(['paper', 'artboard', 'blueprint'].map((n) => [margin(n).column({ at: 1, of: 1 }), margin(n).column(null)]), [['', ''], ['', ''], ['', '']]);
});

test('the urgency marks read !05 !07, • 05  • 07 and [!05][!07]', () => {
  assert.deepEqual(['paper', 'artboard', 'blueprint'].map((n) => marks(n, [5, 7])), ['!05 !07', '• 05  • 07', '[!05][!07]']);
});

test('past three urgent workspaces the marks end in a count of the rest', () => {
  assert.deepEqual(['paper', 'artboard', 'blueprint'].map((n) => marks(n, [2, 3, 5, 7, 9])), ['!02 !03 !05 +2', '• 02  • 03  • 05  +2', '[!02][!03][!05][+2]']);
});

test('no urgent workspace draws no mark', () => {
  assert.deepEqual(['paper', 'artboard', 'blueprint'].map((n) => margin(n).marks([])), [[], [], []]);
});

test("the marks are danger red in Paper, accent dots before ink in Artboard and amber in Blueprint, set off from the title", () => {
  const colors = (n) => [...new Set(margin(n).marks([5, 7]).map((s) => s.color))];
  assert.deepEqual(['paper', 'artboard', 'blueprint'].map(colors), [['#C8381E'], ['#3D5AFE', '#15171B'], ['#FFB547']]);
  assert.deepEqual(['paper', 'artboard', 'blueprint'].map((n) => margin(n).marks([5])[0].text.slice(0, 4)), ['   !', '   •', '   [']);
});

const hifiLaunch = () => launcherLook(checkTokens(validateTheme(theme('hi-fi'))));

test("Hi-Fi's launcher lights its cursor row: LAUNCH · APPS, 3 MATCHES, a lamp slot, an amber-backlit #413A29 row with amber name and ink category", () => {
  const h = hifiLaunch();
  assert.deepEqual([h.label.text('apps'), h.count(3), h.slot], ['LAUNCH · APPS', '3 MATCHES', 'lamp']);
  assert.deepEqual([h.cursor.fill, h.cursor.text, h.cursor.detail, h.cursor.glow], ['#413A29', '#FABD2F', '#EBDBB2', '#FABD2F']);
  assert.deepEqual([h.prompt.text, h.prompt.color, h.caret], ['›', '#FABD2F', 'block']);
  assert.equal(h.legendLine('apps'), 'W WINDOWS  V CLIPBOARD  : EMOJI  = CALC  > COMMANDS  J K · ↵ · ESC');
});

test("Blueprint's launcher keeps its slashes, numbers, cyan cursor and J/K tail beside Hi-Fi's", () => {
  const b = look('blueprint');
  assert.deepEqual([b.label.text('apps'), b.slot, b.cursor.fill, b.legend('apps').tail, b.prompt.text], ['LAUNCH // APPS', 'number', '#7FE3F0', 'J/K · ↵ · ESC', '>']);
  assert.equal(b.cursor.glow ?? '', '');
});
