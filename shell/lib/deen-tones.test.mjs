import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

// Artboard's light board colours; on a dark scheme these pages would draw light tints, so they read plainTones(tokens) instead.
const LIGHT = ['#EEF1FF', '#2638C9', '#F2F3F6', '#F6F7F9', '#6C83FF', '#E3E6EB', '#E9ECF1', '#1E8E5A', '#8A909B', '#B4380B', '#FFF1E8'];
const FILES = ['deen.qml', 'DeenDuas.qml', 'DeenHadith.qml', 'DeenPrayer.qml', 'DeenRead.qml', 'Tailscale.qml'];
const read = (f) => readFileSync(new URL(`../${f}`, import.meta.url), 'utf8');

test('Deen and Tailscale name none of Artboard\'s board colours', () => {
  for (const f of FILES) {
    const text = read(f).toUpperCase();
    assert.deepEqual(LIGHT.filter((h) => text.includes(h)), [], f);
  }
});

test('the app root hands its pages the plain tones of the current theme', () => {
  assert.match(read('deen.qml'), /tones: L\.plainTones\(theme\.tokens\)/);
});

test('Tailscale\'s plain tiles draw the theme\'s card, not a literal white', () => {
  assert.doesNotMatch(read('Tailscale.qml'), /"#FFFFFF"/i);
});
