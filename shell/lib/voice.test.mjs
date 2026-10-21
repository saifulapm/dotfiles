import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { parseToml } from './toml.mjs';
import { launcherLook, islandLook, osdLook, listLook, marginLook, leaseLook, MODES, inOrder } from './voice.mjs';
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
  assert.deepEqual(MODES, ['apps', 'windows', 'clipboard', 'emoji', 'calculator', 'commands']);
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

test('inside a mode the legend keeps to the moving keys and drops the prefixes', () => {
  for (const n of ['paper', 'artboard', 'blueprint']) {
    const l = look(n).legend('clipboard');
    assert.deepEqual(l.keys, [], n);
    assert.match(l.tail, /j\/k.*↵.*esc/i, n);
  }
});

test('the legend reads as one line for the state and the footer checks', () => {
  assert.equal(look('blueprint').legendLine('apps'), '[W] WINDOWS  [V] CLIPBOARD  [:] EMOJI  [=] CALC  [>] COMMANDS  J/K · ↵ · ESC');
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
  assert.equal(b.tile, null);
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

// The lease slot's words, in each theme's voice, as the m21 boards draw them (XX2P8V57).
const leaseParts = (name, who, left) => {
  const l = leaseLook(theme(name));
  return [l.mark, l.words(who), l.time(left)].filter((x) => x).join(' ');
};

test("the lease slot reads each board's words, with the time left as mm:ss", () => {
  assert.equal(leaseParts('paper', 'claude', 872000), '■ AGENT CLAUDE 14:32');
  assert.equal(leaseParts('artboard', 'claude', 872000), '● Agent · claude 14:32');
  assert.equal(leaseParts('blueprint', 'claude', 872000), '[ AGENT ] CLAUDE T−14:32');
  assert.equal(leaseLook(theme('paper')).time(7200000), '120:00');
  assert.equal(leaseLook(theme('paper')).time(41200), '00:42');
});

test("Paper's time is serif, Artboard's dot is its blue, Blueprint draws in cyan", () => {
  const p = leaseLook(theme('paper'));
  assert.equal(p.timeFont, 'Instrument Serif');
  assert.equal(leaseLook(theme('artboard')).markColor, '#6C83FF');
  const b = leaseLook(theme('blueprint'));
  assert.deepEqual([b.text, b.timeColor], ['#7FE3F0', '#7FE3F0']);
});

test("the last minute takes each theme's warning: Paper's sheet and vermilion, Artboard's danger chip, Blueprint's amber", () => {
  const p = leaseLook(theme('paper')).warning;
  assert.deepEqual([p.fill, p.frame, p.time, p.text], ['#F1E9D8', '#C8381E', '#C8381E', '#1C1915']);
  const a = leaseLook(theme('artboard')).warning;
  assert.equal(a.time, '#CF222E');
  assert.ok(a.chip, 'Artboard puts the time in a chip');
  assert.equal(leaseLook(theme('blueprint')).warning.time, '#FFB547');
});

test('a holder any caller names is one line without bidi controls', () => {
  assert.equal(leaseLook(theme('paper')).words('cl\naude\u202e x'), 'AGENT CL AUDE X');
  assert.equal(leaseLook(theme('artboard')).words('\u202eclaude'), 'Agent · claude');
});

test("the lease card names when it unlocked, and Artboard and Blueprint draw a bar of the time left (XX2P8V57)", () => {
  const p = leaseLook(theme('paper'));
  const a = leaseLook(theme('artboard'));
  const b = leaseLook(theme('blueprint'));
  assert.deepEqual([p.unlocked('14:20'), a.unlocked('14:20'), b.unlocked('14:20')], ['UNLOCKED 14:20', 'unlocked 14:20', 'UNLOCKED 14:20']);
  assert.deepEqual([p.bar, a.bar, b.bar], [null, 'round', 'blocks']);
  assert.equal(p.hint, '↵ lock now · esc close');
  assert.equal(a.hint, '↵ lock now · esc close');
});
