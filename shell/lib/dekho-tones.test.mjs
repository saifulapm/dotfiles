import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const files = ['dekho', 'DekhoBrowse', 'DekhoHome', 'DekhoPerson', 'DekhoReleases', 'DekhoStrip', 'DekhoTitle'];
const read = (n) => readFileSync(new URL(`../${n}.qml`, import.meta.url), 'utf8');
const ARTBOARD = /#(EEF1FF|2638C9|F2F3F6|F6F7F9|6C83FF|E3E6EB|E9ECF1|1E8E5A|8A909B|B4380B|FFF1E8)/i;

test('no Dekho surface names an Artboard board colour; each reads the theme\'s table', () => {
  for (const n of files) assert.doesNotMatch(read(n), ARTBOARD, `${n}.qml`);
});

test('the app root draws the table from the theme\'s tokens', () => {
  assert.match(read('dekho'), /tones: L\.plainTones\(theme\.tokens\)/);
});

test('no plain branch fills with a literal white', () => {
  for (const n of files) assert.doesNotMatch(read(n), /plain \? "#FFFFFF"/i, `${n}.qml`);
});
