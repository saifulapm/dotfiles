import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { parseToml } from './toml.mjs';
import { validateTheme, checkTokens } from './theme.mjs';
import { cards, cardName, tagline, windowLook } from './themes.mjs';
import { marginLook, mark, launcherLook, listLook, islandLook, leaseLook, sendingLook, downloadingLook, clockLook } from './voice.mjs';
import { lockLook } from './lock-look.mjs';

// shell.json as theme-render writes it, then as the shell reads it.
const rendered = (n) => validateTheme(parseToml(readFileSync(new URL(`../../themes/${n}/theme.toml`, import.meta.url), 'utf8')));
const shell = (n) => checkTokens(rendered(n));

test('shell.json keeps Hi-Fi\'s voice engraved, and the shell reads it as Blueprint\'s layout with no marks', () => {
  assert.equal(rendered('hi-fi').type.voice, 'engraved');
  assert.equal('engraved' in rendered('blueprint').type, false);
  const t = shell('hi-fi');
  assert.equal(t.type.voice, 'bracket');
  assert.equal(t.type.engraved, true);
  assert.equal(shell('blueprint').type.engraved, undefined);
  assert.equal(checkTokens(t).type.engraved, true, 'a second check keeps it');
});

test('the picker\'s cards read Hi-Fi the same way', () => {
  const [hifi] = cards([rendered('hi-fi')]);
  assert.deepEqual([hifi.type.voice, hifi.type.engraved], ['bracket', true]);
});

test('a mark is Blueprint\'s brackets, and bare when engraved', () => {
  assert.equal(mark(false, '03'), '[03]');
  assert.equal(mark(false, 'AGENT', ' '), '[ AGENT ]');
  assert.equal(mark(true, '03'), '03');
  assert.equal(mark(true, 'AGENT', ' '), 'AGENT');
});

test('the Hi-Fi margins read Blueprint\'s words with no brackets; Blueprint keeps them', () => {
  const view = { idx: 3, app: 'foot', title: '~' };
  const right = { sync: null, goal: null, mail: 0, wifi: 'wifi', battery: null };
  const now = new Date(2026, 10, 1);
  const hifi = marginLook(shell('hi-fi'));
  assert.equal(hifi.number(3), '03');
  assert.equal(hifi.column({ at: 1, of: 2 }), ' 1 / 2');
  assert.deepEqual(hifi.marks([2, 5, 7, 9]).map((s) => s.text), ['   !02 !05 !07 +1']);
  assert.doesNotMatch(JSON.stringify(hifi.drawn(view, now, right)), /[[\]]/);
  const blueprint = marginLook(shell('blueprint'));
  assert.equal(blueprint.number(3), '[03]');
  assert.equal(blueprint.column({ at: 1, of: 2 }), ' [1 / 2]');
  assert.deepEqual(blueprint.marks([2, 5, 7, 9]).map((s) => s.text), ['   [!02][!05][!07][+1]']);
});

test('the Hi-Fi lock draws Blueprint\'s sheet, its status and hint bare', () => {
  const l = lockLook(shell('hi-fi'), 'saiful');
  assert.equal(l.kind, 'sheet');
  assert.equal(l.status.text, 'LOCKED');
  assert.equal(l.hint, '↵ UNLOCK');
  const b = lockLook(shell('blueprint'), 'saiful');
  assert.deepEqual([b.kind, b.status.text, b.hint], ['sheet', '[LOCKED]', '[↵] UNLOCK']);
  assert.equal(lockLook(shell('paper'), 'saiful').kind, 'print');
});

test('the Hi-Fi card reads Hi-fi, BRUSHED · AMBER · DIAL, and frames its focused window in amber', () => {
  const t = shell('hi-fi');
  assert.equal(cardName(t).text, 'Hi-fi');
  assert.equal(tagline(t).text, 'BRUSHED · AMBER · DIAL');
  assert.equal(tagline(shell('blueprint')).text, 'GRID // GLOW // CUT');
  assert.equal(windowLook(t, true).frame.color, '#FABD2F');
});

test('the shared looks draw Blueprint\'s keys and labels bare in Hi-Fi, and Blueprint keeps its marks', () => {
  const hifi = shell('hi-fi');
  const blueprint = shell('blueprint');
  const at = (t) => ({
    launcher: launcherLook(t).legend('apps').keys.map((k) => k.key).join(' '),
    list: listLook(t).keys([['j/k', 'move'], ['esc', '']]).map((k) => k.key).join(' '),
    island: islandLook(t).appLabel('Chromium'),
    lease: [leaseLook(t).slot.label.text, ...leaseLook(t).card.keys.map((k) => k[0])].join(' '),
    sending: sendingLook(t).parts[0].text(),
    downloading: downloadingLook(t).head.left,
    calendar: clockLook(t).grid.header,
  });
  const bare = at(hifi);
  for (const [k, v] of Object.entries(bare)) assert.doesNotMatch(v, /[[\]]/, `${k}: ${v}`);
  assert.equal(bare.island, 'CHROMIUM');
  assert.equal(islandLook(hifi).brackets, false);
  const marked = at(blueprint);
  for (const [k, v] of Object.entries(marked)) assert.match(v, /\[/, `${k}: ${v}`);
  assert.equal(marked.island, '[ CHROMIUM ]');
  assert.equal(islandLook(blueprint).brackets, true);
});
