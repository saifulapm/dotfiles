import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';
import { schemeTokens, schemeNames } from './colorscheme-file.mjs';
import { contrast } from './theme.mjs';
import { plainTones, launcherLook, islandLook, osdLook, listLook, marginLook, leaseLook, sendingLook, downloadingLook, chipLook, clockLook, captureLook, MODES, inOrder } from './voice.mjs';
import { parseQuery } from './launcher.mjs';

const SCHEMES = schemeNames();
// A look's data as JSON reads it: its functions drop out, so what is left is every value it draws with.
const data = (look) => JSON.parse(JSON.stringify(look));
const look = (name) => launcherLook(schemeTokens(name));

test("the launcher draws Artboard's board: a search glyph, an Apps pill, icon tiles and a tinted rounded cursor with a return badge, and nothing more", () => {
  assert.deepEqual(data(look('artboard')), {
    prompt: { text: '', color: '#57606A' },
    query: { font: 'Maple Mono', size: 20 },
    label: { kind: 'pill', fill: '#EEF1FF', color: '#3D5AFE' },
    name: { font: 'Maple Mono', size: 15, weight: 500, spacing: 0, color: '#15171B' },
    detail: { font: 'Maple Mono', size: 12, italic: false, color: '#57606A' },
    cursor: { fill: '#EEF1FF', text: '#2638C9', detail: '#57606A', radius: 10, weight: 600, badge: '↵' },
    small: { font: 'Maple Mono', size: 11, spacing: 0, color: '#57606A' },
    tile: { size: 32, radius: 9, fill: '#F2F3F6' },
    chip: { fill: 'transparent', key: '#57606A' },
    keyChip: { fill: '#F2F3F6', text: '#57606A', border: 0, borderColor: 'transparent', cursorFill: '#FFFFFF', cursorText: '#2638C9', cursorBorder: 'transparent', radius: 6, size: 11, spacing: 0 },
  });
});

test("a dark scheme's lit row and pill draw in its own tint, its words moved toward the ink until they read, and its keys its own tokens", () => {
  const g = look('gruvbox-dark');
  assert.deepEqual([g.label.color, g.cursor.detail, g.cursor.fill, g.cursor.text], ['#8DAA9B', '#AFA089', '#353A38', '#8DAA9B']);
  assert.deepEqual([g.name.color, g.detail.color, g.chip.key, g.keyChip.cursorFill], ['#EBDBB2', '#A89984', '#A89984', '#282828']);
  const r = look('rose-pine-dawn');
  assert.deepEqual([r.label.color, r.cursor.detail, r.keyChip.cursorFill], ['#6C5E88', '#656183', '#FAF4ED']);
});

test('every mode is named in the plain voice', () => {
  assert.deepEqual(MODES, ['apps', 'windows', 'clipboard', 'emoji', 'calculator', 'commands', 'reminder', 'colorschemes']);
  assert.deepEqual(MODES.map((m) => look('artboard').label.text(m)), ['Apps', 'Windows', 'Clipboard', 'Emoji', 'Calculator', 'Commands', 'Reminder', 'Colorschemes']);
});

test('the apps legend names the five prefixes, then the moving keys in one short tail', () => {
  for (const n of SCHEMES) {
    const l = look(n).legend('apps');
    assert.deepEqual(l.keys.map((k) => `${k.key} ${k.word}`), ['w windows', 'v clipboard', ': emoji', '= calculator', '> commands'], n);
    assert.equal(l.tail, 'j/k · ↵ · esc', n);
  }
});

test('inside a mode the legend keeps to the moving keys and drops the prefixes; clipboard adds Shift+Enter copy and reminder its delete', () => {
  const a = look('artboard');
  assert.deepEqual(a.legend('emoji'), { keys: [], tail: 'j/k · ↵ · esc' });
  assert.deepEqual(a.legend('clipboard').keys, [{ key: '⇧↵', word: 'copy' }]);
  assert.deepEqual(a.legend('reminder').keys, [{ key: 'd', word: 'delete' }]);
});

test('the legend reads as one line for the state and the footer checks', () => {
  assert.equal(look('artboard').legendLine('apps'), 'w windows  v clipboard  : emoji  = calculator  > commands  j/k · ↵ · esc');
  assert.equal(look('artboard').legendLine('reminder'), 'd delete  j/k · ↵ · esc');
});

test("a row's global key reads as niri writes it, and no key reads empty", () => {
  assert.equal(look('artboard').rowKey('Mod+Shift+7'), 'Mod+Shift+7');
  assert.equal(look('artboard').rowKey(undefined), '');
});

test("a capture row shows its long detail, not its tool", () => {
  assert.equal(look('artboard').rowDetail({ title: 'Annotate region', detail: 'satty on a region of the screen', tool: 'satty' }), 'satty on a region of the screen');
  assert.equal(look('artboard').rowDetail({ title: 'lock', detail: 'Lock‮ the screen' }), 'Lock the screen');
});

test('reminder mode heads its pending rows with their count', () => {
  assert.deepEqual(look('artboard').pendingHead(2), { text: 'Pending · 2', right: '' });
});

test('before the theme loads the launcher draws the plain look in black and white', () => {
  const u = launcherLook(null);
  assert.equal(u.label.text('apps'), 'Apps');
  assert.deepEqual([u.prompt.color, u.name.color, u.label.color, u.cursor.detail, u.chip.key, u.keyChip.cursorFill], ['gray', 'white', 'white', 'gray', 'gray', 'black']);
  assert.deepEqual([u.query.size, u.cursor.radius, u.cursor.badge, u.legend('apps').tail], [20, 10, '↵', 'j/k · ↵ · esc']);
});

test('each prefix the apps footer names opens its mode', () => {
  const prefixes = look('artboard').legend('apps').keys.map((k) => k.key);
  assert.deepEqual(prefixes.map((p) => parseQuery(p + ' x').mode), ['windows', 'clipboard', 'emoji', 'calculator', 'commands']);
});

test('a name cannot reorder itself with bidi controls, so it draws in the order it is spelt', () => {
  const l = look('artboard');
  assert.equal(l.title('Zf ‮evil'), 'Zf evil');
  assert.equal(l.detailText('⁧RTLover⁩'), 'RTLover');
});

const island = (name) => islandLook(schemeTokens(name));

test("the notification has a 40 px rounded tile, the app and now in the island's head tone, and a 15 px bold summary, in every scheme", () => {
  assert.deepEqual(data(island('artboard')), {
    width: 440,
    age: 'now',
    pad: { x: 16, top: 14, bottom: 14 },
    head: { font: 'Maple Mono', size: 12, spacing: 0, color: '#A3A9B4' },
    summary: { font: 'Maple Mono', size: 15, weight: 600, spacing: 0, color: '#FFFFFF' },
    body: { font: 'Maple Mono', size: 13, color: '#C9CED6' },
    control: { color: '#C9CED6' },
    tile: { size: 40, radius: 12, fill: '#2B2F36' },
  });
  for (const n of SCHEMES) {
    const tones = plainTones(schemeTokens(n)).island;
    const l = island(n);
    assert.deepEqual([l.head.color, l.summary.color, l.body.color, l.tile.fill, l.width, l.tile.size], [tones.head, tones.summary, tones.body, tones.tile, 440, 40], n);
  }
  const a = island('artboard');
  assert.deepEqual([a.appText('Chromium'), a.glyph('chromium'), a.glyph(''), a.summaryText('Download complete')], ['Chromium', 'C', '•', 'Download complete']);
});

test('an empty app name draws no label', () => {
  assert.deepEqual([island('artboard').appText(''), island('artboard').appText(null)], ['', '']);
});

test('an app name cannot reorder its label with bidi controls', () => {
  assert.equal(island('artboard').appText('a‮b'), 'ab');
});

test('a notification cannot draw control characters: BEL and ESC drop out of its app, title and body, and the body keeps its lines and tabs', () => {
  for (const n of SCHEMES) {
    const l = island(n);
    assert.equal(l.summaryText('A\u0007\u001b[31mred'), 'A[31mred', n);
    assert.equal(l.appText('Chro\u001bmium\u009b'), 'Chromium', n);
    assert.equal(l.bodyText('one\u0000two\nthree\tfour\u007f'), 'onetwo\nthree\tfour', n);
  }
});

test("a newline in a notification's app or summary keeps each to one line, and the body cannot reorder itself", () => {
  const a = island('artboard');
  assert.equal(a.appText('two\nlines'), 'two lines');
  assert.equal(a.summaryText('a\r\n\tb'), 'a b');
  assert.equal(a.bodyText('x‮yz\nnext'), 'xyz\nnext');
});

test('before the theme loads the island still has a whole notification and OSD look', () => {
  const i = islandLook(null);
  assert.deepEqual([i.appText('x'), i.age, i.width, i.tile.size], ['x', 'now', 440, 40]);
  const o = osdLook(null);
  assert.deepEqual([o.valueText(7), o.lit.color, o.unlit.color, o.bars], ['7', 'white', 'gray', 'round']);
});

const osd = (name) => osdLook(schemeTokens(name));

test('the OSD lights a twentieth for every 5 %, rounded, and clamps', () => {
  assert.deepEqual([0, 62, 100, 140, -3].map((v) => osd('artboard').litCount(v)), [0, 12, 20, 20, 0]);
});

test("the OSD is one rounded bar in the scheme's bar tone on its island tile, with the value beside it, for volume and brightness alike", () => {
  assert.deepEqual(data(osd('artboard')), {
    width: 300,
    height: 40,
    bars: 'round',
    lit: { color: '#6C83FF' },
    unlit: { color: '#2B2F36' },
    value: { font: 'Maple Mono', size: 13, weight: 600, color: '' },
  });
  for (const n of SCHEMES) {
    const t = plainTones(schemeTokens(n));
    assert.deepEqual([osd(n).lit.color, osd(n).unlit.color, osd(n).bars], [t.bar, t.island.tile, 'round'], n);
  }
  assert.deepEqual([osd('artboard').valueText(62), osd('artboard').valueText(5)], ['62', '5']);
});

const OCR = { kind: 'ocr', title: 'Text copied', detail: '214 characters', swatch: null };
const COLOUR = { kind: 'colour', title: 'Copied', detail: '#C8381E', swatch: '#C8381E' };
const QR = { kind: 'qr', title: 'QR code copied', detail: '', swatch: null };
const MISS = { kind: 'ocr', title: '', detail: 'No text found', swatch: null };

test("the capture result is the notification card from Capture, the result as the summary", () => {
  const a = captureLook(schemeTokens('artboard'));
  assert.deepEqual(Object.keys(a), ['note']);
  assert.deepEqual(a.note(OCR), { app: 'Capture', summary: 'Text copied · 214 characters', body: 'eng + ben · from region', swatch: null, icon: '', files: [] });
  assert.deepEqual([a.note(COLOUR).summary, a.note(COLOUR).body, a.note(COLOUR).swatch], ['Copied #C8381E', 'colour picked', '#C8381E']);
  assert.deepEqual([a.note(QR).summary, a.note(QR).body], ['QR code copied', 'from region']);
  assert.equal(a.note(MISS).summary, 'No text found');
  assert.equal(captureLook(null).note(OCR).app, 'Capture');
});

const list = (name) => listLook(schemeTokens(name));

test("a list surface's heading is the pill word, and its current tab the launcher's pill", () => {
  assert.deepEqual([list('artboard').heading('control', 'audio'), list('artboard').heading('notifications', '')], ['Control', 'Notifications']);
  assert.deepEqual(list('artboard').tab, { fill: '#EEF1FF', text: '#3D5AFE', radius: 8 });
  assert.deepEqual(list('gruvbox-dark').tab, { fill: '#353A38', text: '#8DAA9B', radius: 8 });
  assert.equal(list('artboard').tabText('Wi-Fi'), 'Wi-Fi');
});

test("a list surface's legend keys read in plain words", () => {
  const pairs = [['tab', 'section'], ['j/k', 'move'], ['esc', 'close']];
  assert.deepEqual(list('artboard').keys(pairs).map((k) => `${k.key} ${k.word}`), ['tab section', 'j/k move', 'esc close']);
  assert.equal(list('artboard').keyText('Mod ⇧ t'), 'Mod ⇧ t');
  assert.equal(list('artboard').keyText('a‮b'), 'ab');
});

test("a list surface keeps the launcher's cursor row and draws no rules", () => {
  for (const n of SCHEMES) {
    assert.deepEqual(list(n).cursor, look(n).cursor, n);
    assert.equal(list(n).rule, undefined, n);
  }
  // The list look has no rule, so a QML that still read look.rule.color would throw and draw its slot in Qt's default colour.
  const shell = new URL('../', import.meta.url).pathname;
  const reads = readdirSync(shell).filter((f) => f.endsWith('.qml') && /\blook\.rule\.color/.test(readFileSync(shell + f, 'utf8')));
  assert.deepEqual(reads, []);
});

test("a list surface writes an entry's age in whole units, floored: now under a minute, then minutes, hours and days", () => {
  const S = 1000, M = 60 * S, H = 60 * M, D = 24 * H;
  const ages = [0, 59 * S, 60 * S, 5 * M, 59 * M, 60 * M, 3 * H, 23 * H + 59 * M, 24 * H, 2 * D + 5 * H];
  assert.deepEqual(ages.map((ms) => list('artboard').ageText(ms)), ['now', 'now', '1m', '5m', '59m', '1h', '3h', '23h', '1d', '2d']);
});

test("the notification centre's group head names the app on one line and its count, or the count alone", () => {
  assert.deepEqual([list('artboard').groupHead('Fire\nfox', 3), list('artboard').groupHead('', 1), list('artboard').groupHead(null, 2)], ['Fire fox · 3', '1', '2']);
});

test('a polkit request cannot reorder what it asks with bidi controls, and keeps its lines', () => {
  assert.equal(inOrder('run ‮evil.sh as root'), 'run evil.sh as root');
  assert.equal(inOrder('a⁦b⁩\nc‪‬d'), 'ab\ncd');
  assert.equal(inOrder(undefined), '');
});

const margin = (name) => marginLook(schemeTokens(name));
const foot = { idx: 2, app: 'foot', title: '~' };
// Sunday 18 October 2026, local time.
const SUN = new Date(2026, 9, 18, 9, 30);
const right = { sync: '', goal: { title: 'Ship v2', left: '3d' }, wifi: 'wifi', battery: '82%' };

test('the top-left margin reads Page 02 / foot — ~, and an empty workspace only its number', () => {
  for (const n of SCHEMES) {
    assert.equal(margin(n).drawn(foot, SUN, right).left, 'Page 02 / foot — ~', n);
    assert.equal(margin(n).drawn({ idx: 4, app: null, title: null }, SUN, right).left, 'Page 04', n);
  }
});

test('the top-right margin reads Ship v2 · 3d Wi-Fi 82% Sun 18 Oct, a sync failure first and unread mail after the goal', () => {
  const a = margin('artboard');
  assert.equal(a.date(SUN), 'Sun 18 Oct');
  assert.equal(a.drawn(foot, SUN, right).right, 'Ship v2 · 3d Wi-Fi 82% Sun 18 Oct');
  assert.equal(a.drawn(foot, SUN, { ...right, sync: 'sync !' }).right, 'sync ! Ship v2 · 3d Wi-Fi 82% Sun 18 Oct');
  assert.equal(a.drawn(foot, SUN, { ...right, mail: 3 }).right, 'Ship v2 · 3d mail 3 Wi-Fi 82% Sun 18 Oct');
  assert.equal(a.drawn(foot, SUN, { ...right, mail: 0 }).right, 'Ship v2 · 3d Wi-Fi 82% Sun 18 Oct');
  assert.deepEqual([a.word('no wifi'), a.word('wifi'), a.word('82%')], ['No Wi-Fi', 'Wi-Fi', '82%']);
  assert.deepEqual([a.goal({ title: 'Read', left: null }), a.goal(null), a.mail(3), a.mail(0)], ['Read', '', 'mail 3', '']);
});

test("the margins draw the number, goal and mail in the scheme's ink, its tail and date muted and its dot in the accent, each moved until it reads on the desk, all of nothing else", () => {
  assert.deepEqual(data(margin('artboard')), {
    numberColor: '#15171B', numberWeight: 600, tailColor: '#535B65', goalColor: '#15171B', goalWeight: 500, dot: true, dotColor: '#3249CE', mailColor: '#15171B', mailWeight: 500, dateColor: '#535B65', spacing: 16,
  });
  const g = margin('gruvbox-dark');
  assert.deepEqual([g.numberColor, g.tailColor, g.goalColor, g.dotColor, g.mailColor, g.dateColor], ['#EBDBB2', '#B1A390', '#EBDBB2', '#89AA9D', '#EBDBB2', '#B1A390']);
});

// The margins sit on the desk, which is the paper under a field washing into the scheme's accent.
test("every scheme's margin words read at 4.5:1 on its paper and on both ends of its field", () => {
  for (const n of SCHEMES) {
    const t = schemeTokens(n);
    const m = margin(n);
    for (const ground of [t.color.paper, t.paper.grade.from, t.paper.grade.to]) {
      for (const k of ['numberColor', 'tailColor', 'goalColor', 'dotColor', 'mailColor', 'dateColor']) {
        assert.ok(contrast(m[k], ground) >= 4.5, `${n} ${k} ${m[k]} on ${ground}: ${contrast(m[k], ground).toFixed(2)}`);
      }
    }
  }
});

// A window's title is its file's name, which anyone who sends a file controls: a newline stacked a second line under the margin rule, and ESC or BEL drew tofu.
test('the margin draws a window title on one line, with no control characters or bidi marks', () => {
  for (const title of ['line1\nline2 INJECT.pdf', 'esc\u001b[31mred\u001b]0;pwn\u0007.pdf', 'a\u0085b\u009bc', 'rtl‮fdp.exe', 'mark‎‏؜s']) {
    const tail = margin('artboard').tail({ idx: 1, app: 'org.pwmt\u0007zathura\n', title });
    assert.doesNotMatch(tail, /[\u0000-\u001f\u007f-\u009f‎‏؜‪-‮⁦-⁩]/, JSON.stringify(tail));
  }
  assert.equal(margin('artboard').tail({ idx: 1, app: 'zathura', title: 'line1\nline2 INJECT.pdf' }), ' / zathura — line1 line2 INJECT.pdf');
  assert.equal(margin('artboard').drawn({ idx: 1, app: 'foot', title: 'a‮b' }, SUN, right).left, 'Page 01 / foot — ab');
});

test('the focused column reads 2 / 3 after the workspace number, and a lone column or no tiled window draws none', () => {
  const a = margin('artboard');
  assert.deepEqual([a.column({ at: 2, of: 3 }), a.column({ at: 1, of: 1 }), a.column(null)], ['  2 / 3', '', '']);
});

test('the urgency marks are accent dots before ink numbers, at most three, then a count of the rest, set off from the title', () => {
  const a = margin('artboard');
  assert.deepEqual(a.marks([5, 7]), [
    { text: '   •', color: '#3249CE' },
    { text: ' 05', color: '#15171B' },
    { text: '  •', color: '#3249CE' },
    { text: ' 07', color: '#15171B' },
  ]);
  assert.equal(a.marks([2, 3, 5, 7, 9]).map((s) => s.text).join(''), '   • 02  • 03  • 05  +2');
  assert.deepEqual(a.marks([2, 3, 5, 7]).at(-1), { text: '  +1', color: '#15171B' });
  assert.deepEqual(a.marks([]), []);
});

const lease = (name) => leaseLook(schemeTokens(name));
const slotText = (l, who, left) => [l.slot.label.text, l.slot.who.text(who), l.time(left)].filter((x) => x).join(' ');

test('the lease slot reads Agent · claude and the time left as m:ss, a #6C83FF dot before it, at 264 by 40', () => {
  const l = lease('artboard');
  assert.equal(slotText(l, 'claude', 872000), 'Agent · claude 14:32');
  assert.deepEqual([l.time(42000), l.time(7200000), l.time(-5)], ['0:42', '120:00', '0:00']);
  assert.deepEqual(data(l.slot), {
    width: 264,
    height: 40,
    pad: 16,
    gap: 10,
    mark: { shape: 'dot', size: 8, color: '#6C83FF' },
    label: { font: 'Maple Mono', size: 13, color: '', weight: 400, spacing: 0, text: '' },
    who: { font: 'Maple Mono', size: 13, color: '#C9CED6', weight: 500, spacing: 0 },
    time: { font: 'Maple Mono', size: 13, color: '#FFFFFF', weight: 500, spacing: 0 },
  });
});

test("the lease's last minute is a #B4380B time on a #FFF1E8 chip and ring", () => {
  assert.deepEqual(lease('artboard').warning, { label: '', time: '#B4380B', chip: '#FFF1E8', ring: '#FFF1E8', mark: '#B4380B' });
});

test('the lease card is a selected frame in the accent, named Island, with its tile, round bar and plain keys', () => {
  const a = lease('artboard').card;
  assert.deepEqual(data(a), {
    width: 440,
    box: { frame: { width: 1.5, color: '#3D5AFE' } },
    label: 'Island',
    ink: '#FFFFFF',
    head: 'Agent · lease',
    headColor: '#A3A9B4',
    unlockedColor: '#C9CED6',
    left: 'left',
    tile: '#2B2F36',
    bar: 'round',
    barFill: '#6C83FF',
    keys: [['↵', 'lock now'], ['esc', 'close']],
  });
  assert.deepEqual([a.who('claude'), a.unlocked('14:05')], ['claude', 'unlocked 14:05']);
  assert.deepEqual(lease('gruvbox-dark').card.box, { frame: { width: 1.5, color: '#83A598' } });
  assert.equal(leaseLook(null).card.box, null);
});

test('a holder any caller names is one line without bidi controls, in the slot and the card', () => {
  assert.equal(lease('artboard').slot.who.text('cl\naude‮ x'), 'Agent · cl aude x');
  assert.equal(lease('artboard').card.who('‮claude'), 'claude');
});

const sending = (name) => sendingLook(schemeTokens(name));

test('the sending slot is a 380 by 40 pill with an upload glyph, the percent in its words and a 6 px rounded bar after them', () => {
  const s = sending('artboard');
  assert.deepEqual([s.width, s.height, s.pad, s.gap, s.mark], [380, 40, 16, 10, { shape: 'upload', size: 16, color: '' }]);
  assert.equal(s.parts.length, 1);
  assert.deepEqual([s.parts[0].text(2, 'nuc', 48), s.parts[0].text(1, 'n‮u\nc', 0), s.parts[0].size, s.parts[0].weight, s.parts[0].name, 'pct' in s], ['Sending 2 files to nuc · 48%', 'Sending 1 file to nu c · 0%', 13, 500, true, false]);
  assert.deepEqual(s.bar, { height: 6, radius: 3, track: '#2B2F36', fill: '#6C83FF' });
  assert.deepEqual(sendingLook(null).bar, { height: 6, radius: 3, track: 'gray', fill: 'white' });
});

test('the downloading slot is 440 wide with a 40 px play tile, YouTube and the folder at 12 px, a 15 px bold line, a 4 px rounded bar and a failed chip', () => {
  const d = downloadingLook(schemeTokens('artboard'));
  assert.deepEqual([d.width, d.height, d.pad, d.gap, d.tile], [440, 76, 16, 6, { size: 40, radius: 12, fill: '#2B2F36' }]);
  assert.deepEqual([d.head.left, d.head.right('audio', '14:32'), d.head.right('video', '14:32'), d.head.right('', '14:32'), d.head.size, d.head.color], ['YouTube', '~/Music/YouTube', '~/Videos/YouTube', '', 12, '#A3A9B4']);
  assert.deepEqual([d.line.size, d.line.weight, d.line.color], [15, 700, '']);
  assert.deepEqual(d.bar, { height: 4, radius: 2, track: '#2B2F36', fill: '#6C83FF' });
  assert.deepEqual(d.chip, { fill: '#FFF1E8', color: '#B4380B', radius: 8, padX: 8, padY: 2 });
  assert.equal('failure' in d, false);
});

const chip = (name) => chipLook(schemeTokens(name));

test("the file chip is a rounded tile-coloured pill beside the card; dragged, a dashed blue slot and a white pill named in ink", () => {
  assert.deepEqual(data(chip('artboard')), {
    font: 'Maple Mono',
    size: 11,
    spacing: 0,
    gap: 6,
    grip: { w: 8, h: 12, r: 1 },
    glyph: { w: 14, h: 14, stroke: 1.3, path: 'M3 1.5h5l3 3v8H3z M8 1.5v3h3' },
    toast: { fill: '#2B2F36', frame: '#2B2F36', text: '#C9CED6', grip: '#A3A9B4', glyph: '#FFFFFF', pad: [8, 10, 8, 10], radius: 10 },
    row: { fill: '#F2F3F6', frame: '#F2F3F6', text: '#57606A', grip: '#8A909B', glyph: '#57606A', pad: [5, 8, 5, 8], radius: 8 },
    cursor: { fill: '#FFFFFF', frame: '#FFFFFF', text: '#57606A', grip: '#8A909B', glyph: '#57606A', pad: [5, 8, 5, 8], radius: 8 },
    empty: { color: '#6C83FF', width: 1.5, content: false },
    drag: { fill: '#FFFFFF', frame: '#3D5AFE', frameWidth: 1.5, text: '#15171B', grip: null, glyph: '#2638C9', pad: [9, 12, 9, 12], gap: 8, size: 12, weight: 500, spacing: 0, radius: 10 },
  });
  const g = chip('gruvbox-dark');
  assert.deepEqual([g.row.text, g.cursor.fill, g.drag.fill, g.drag.frame, g.drag.text], ['#A89984', '#282828', '#282828', '#83A598', '#EBDBB2']);
});

test("a chip reads the file's extension or the count, and the drag image names the file in one line without controls", () => {
  const a = chip('artboard');
  assert.deepEqual([a.label(['/d/IMG_2041.heic']), a.label(['/d/a', '/d/b', '/d/c'])], ['HEIC', '3 FILES']);
  assert.equal(a.name(['/d/IMG_2041.HEIC']), 'IMG_2041.HEIC');
  assert.equal(a.name(['/d/a\nb‮\u0007c.jpg']), 'a bc.jpg');
  assert.equal(a.name(['/d/a', '/d/b']), '2 FILES');
  assert.equal(a.label(['/d/x.he‮ic']), 'HEIC');
});

const clock = (name) => clockLook(schemeTokens(name));

test("the world clock reads Dhaka · home over a bold 26 px time, the offset under each city and #2B2F36 rules", () => {
  const a = clock('artboard');
  assert.deepEqual([a.gridWidth, a.gap, a.city('Dhaka') + a.mark.text, a.mark, 'place' in a, 'offsetWidth' in a], [224, 22, 'Dhaka · home', { text: ' · home' }, false, false]);
  assert.deepEqual([a.homeTime.size, a.homeTime.weight, a.time.size, a.time.weight, a.name.size, a.name.weight], [26, 700, 17, 700, 14, 500]);
  assert.deepEqual([a.homeLabel.color, a.offset.size, a.offset.color, a.rule, a.dayText('yesterday'), a.offsetText('−10h'), a.city('New York')], ['#A3A9B4', 12, '#A3A9B4', undefined, 'yesterday', '−10h', 'New York']);
  assert.equal('head' in a, false);
});

test('the month grid reads October 2026 at 15 px over Sunday weeks, #A3A9B4 weekdays and a pill for today', () => {
  const g = clock('artboard').grid;
  assert.deepEqual(data(g), {
    weekStart: 0,
    weekdays: ['Su', 'Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa'],
    cell: 32,
    rowHeight: 28,
    weekHeight: 28,
    rowGap: 0,
    gap: 6,
    title: { left: { font: 'Maple Mono', size: 15, weight: 500, spacing: 0, color: '' } },
    weekday: { font: 'Maple Mono', size: 11, weight: 400, spacing: 0, color: '#A3A9B4' },
    day: { font: 'Maple Mono', size: 12, weight: 400, spacing: 0, color: '#C9CED6' },
    today: { w: 28, h: 24, radius: 8, inverted: true, fill: '', border: 0, borderColor: '', weight: 700 },
  });
  assert.deepEqual(g.title.parts({ month: 'October', abbr: 'Oct', year: 2026 }), ['October 2026']);
});
