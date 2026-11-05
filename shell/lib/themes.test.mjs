import { test } from 'node:test';
import assert from 'node:assert/strict';
import { cards, step, jump, previewSwitch, cardName, tagline, pickerLook, windowLook, terminalLines, swatches, specimenMargins, panelWidth, cardWidth } from './themes.mjs';
import { schemeTokens } from './colorscheme-file.mjs';

const artboard = schemeTokens('artboard');
const gruvbox = schemeTokens('gruvbox-dark');
const dawn = schemeTokens('rose-pine-dawn');

const names = ['artboard', 'gruvbox-dark', 'rose-pine-dawn'];

test('step moves the cursor by one name and stops at the ends', () => {
  assert.equal(step(names, 'artboard', 1), 'gruvbox-dark');
  assert.equal(step(names, 'rose-pine-dawn', -1), 'gruvbox-dark');
  assert.equal(step(names, 'rose-pine-dawn', 1), 'rose-pine-dawn');
  assert.equal(step(names, 'artboard', -1), 'artboard');
});

test('each card names its scheme in Maple Mono 16 px bold and says whether it is light or dark', () => {
  assert.deepEqual([artboard, gruvbox].map((t) => { const n = cardName(t); return [n.text, n.font, n.size, n.weight]; }), [
    ['Artboard', 'Maple Mono', 16, 700],
    ['Gruvbox-dark', 'Maple Mono', 16, 700],
  ]);
  assert.deepEqual([artboard, gruvbox].map((t) => tagline(t).text), ['Light', 'Dark']);
});

test("the picker is Artboard's board in every scheme: Themes, 5 themes, Current and a 1.5 px outline, no shadow", () => {
  const l = pickerLook(artboard);
  assert.deepEqual([l.header(5, 'artboard').title, l.header(5, 'artboard').sub, l.header(5, 'artboard').right], ['Themes', '5 themes', '']);
  assert.deepEqual([l.tag(true, true).text, l.tag(false, true).text, l.tag(false, false)], ['Current', '↵', null]);
  assert.deepEqual(l.tile, { fill: '#F6F7F9', border: { width: 0, color: 'transparent' }, radius: 12, pad: 10 });
  assert.deepEqual(l.cursor, { fill: '#FFFFFF', border: { width: 1.5, color: '#3D5AFE' }, radius: 12 });
  assert.deepEqual(l.legend(5).map((k) => `${k.key} ${k.word}`), ['j/k choose', '1–5 jump', '↵ apply']);
  assert.equal(l.esc, 'esc');
  assert.deepEqual([pickerLook(gruvbox).cursor.fill, pickerLook(gruvbox).cursor.border.color], ['#282828', '#83A598']);
});

test('a specimen window is framed as niri frames it: 1 px ink when focused, the line colour when not, square, no shadow', () => {
  assert.deepEqual(windowLook(gruvbox, true), { fill: '#282828', frame: { width: 1, color: '#EBDBB2' }, radius: 0 });
  assert.deepEqual(windowLook(gruvbox, false), { fill: '#282828', frame: { width: 1, color: gruvbox.color.line }, radius: 0 });
});

test('the terminal reads four lines in the ANSI colours: blue path, red prompt, green pass, yellow hash', () => {
  const lines = terminalLines(gruvbox);
  assert.equal(lines.length, 4);
  assert.deepEqual(lines.map((l) => l.map((r) => r.text).join('')), [
    '~/S/g/dotfiles ❯ just test', '✓ 42 passed · 0.9 s', '~/S/g/dotfiles ❯ git log -1', 'a1e9e71 gruvbox-… on the shelf',
  ]);
  assert.deepEqual([lines[0][0].color, lines[0][1].color, lines[1][0].color, lines[3][0].color], ['#458588', '#CC241D', '#98971A', '#D79921']);
});

test('the palette strip is ink, ANSI 1 to 6 and the paper', () => {
  assert.deepEqual(swatches(gruvbox), ['#EBDBB2', '#CC241D', '#98971A', '#D79921', '#458588', '#B16286', '#689D6A', '#1D2021']);
});

test('the specimen margins read one scene: Page 03 / foot', () => {
  const m = specimenMargins(artboard);
  assert.deepEqual([m.number + m.tail, m.goal + m.date, m.rules], ['Page 03 / foot — ~', 'Ship v2 · 3d  Sun 18 Oct', true]);
});

test('before the theme loads the picker still has a whole look', () => {
  const l = pickerLook(null);
  assert.deepEqual([l.header(3, '').title, l.tag(true, false).text, l.cursor.border.width, l.legend(3).length], ['Themes', 'Current', 1.5, 3]);
});

test('a card plays the crossfade in miniature, slowed with the desktop', () => {
  assert.deepEqual(previewSwitch(1), { kind: 'fade', ms: 260 });
  assert.equal(previewSwitch(20).ms, 5200);
});

test('a digit jumps to its card, and one with no card changes nothing', () => {
  assert.equal(jump(names, 'artboard', 3), 'rose-pine-dawn');
  assert.equal(jump(names, 'rose-pine-dawn', 1), 'artboard');
  assert.equal(jump(names, 'artboard', 7), 'artboard');
  assert.equal(jump(names, 'artboard', 0), 'artboard');
});

test('a themes.json entry the shell would refuse gets no card, and the rest keep theirs', () => {
  const noNiri = { ...artboard, name: 'noniri' }; delete noNiri.niri;
  const noAnsi = { ...artboard, name: 'noansi', color: { ...artboard.color } }; delete noAnsi.color.ansi;
  const noPaper = { ...gruvbox, name: 'nopaper' }; delete noPaper.paper;
  const list = cards([dawn, noNiri, noAnsi, noPaper, null, 'x', gruvbox]);
  assert.deepEqual(list.map((t) => t.name), ['rose-pine-dawn', 'nopaper', 'gruvbox-dark']);
  assert.deepEqual(list[1].paper, {});
  assert.deepEqual(cards({ not: 'a list' }), []);
});

test('a forged theme name draws on one line, in the order it is spelt', () => {
  const t = { ...dawn, name: 'pa\nper\u202Eevil' };
  assert.equal(cardName(t).text, 'Pa perevil');
  assert.equal(terminalLines(t)[3][1].text, 'pa perev… on the shelf');
  assert.equal(cardName({ ...gruvbox, name: 'gruv\tbox' }).text, 'Gruv box');
});

test('a long theme name is cut in the terminal line, so the line fits its window', () => {
  assert.equal(terminalLines({ ...dawn, name: 'n'.repeat(200) })[3][1].text, 'nnnnnnnn… on the shelf');
  assert.equal(terminalLines(artboard)[3][1].text, 'artboard on the shelf');
});

test('the picker gives every card 326 px up to four themes on a wide screen', () => {
  assert.deepEqual([1, 2, 3, 4].map((n) => cardWidth(n, 2048)), [326, 326, 326, 326]);
  assert.equal(panelWidth(4, 2048), 1396);
});

test('past four themes the cards shrink and the panel stays at its four-card width', () => {
  assert.equal(panelWidth(5, 2048), 1396);
  assert.equal(cardWidth(5, 2048), 257.6);
});

test('on a narrow screen four cards shrink to fit inside a 24 px gutter', () => {
  assert.equal(panelWidth(4, 1200), 1152);
  assert.equal(cardWidth(4, 1200), 265);
});

