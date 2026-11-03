import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { parseToml } from './toml.mjs';
import { validateTheme, checkTokens } from './theme.mjs';
import { lockLook } from './lock-look.mjs';

const load = (name) => validateTheme(parseToml(readFileSync(new URL(`../../themes/${name}/theme.toml`, import.meta.url), 'utf8')));

test('Paper: a 220 px Instrument Serif clock in ink over an italic serif date', () => {
  assert.deepEqual(lockLook(load('paper'), 'saiful'), {
    kind: 'print',
    status: { text: 'LOCKED', color: '#575653' },
    clock: { family: 'Instrument Serif', px: 220, bold: false, tracking: -4.4, fill: '#1C1915', stroke: 'transparent' },
    date: { format: 'dddd, d MMMM', caps: false, family: 'Instrument Serif', px: 30, italic: true, tracking: 0, color: '#575653' },
    prompt: 'PASSWORD FOR SAIFUL',
    hint: 'press return to unlock',
  });
});

test('Artboard: a 96 px bold Maple Mono clock on a card, the date as its frame label', () => {
  assert.deepEqual(lockLook(load('artboard'), 'saiful'), {
    kind: 'card',
    status: { text: 'Locked', color: '#15171B' },
    clock: { family: 'Maple Mono', px: 96, bold: true, tracking: -4.8, fill: '#15171B', stroke: 'transparent' },
    date: { format: 'dddd, d MMMM', caps: false, family: 'Maple Mono', px: 12, italic: false, tracking: 0, color: '#3D5AFE' },
    prompt: '',
    hint: 'Password for saiful · ↵ to unlock',
  });
});

test('Blueprint: a hollow 200 px clock outlined in the accent, the date on a dimension line', () => {
  assert.deepEqual(lockLook(load('blueprint'), 'saiful'), {
    kind: 'sheet',
    status: { text: '[LOCKED]', color: '#FFB547' },
    clock: { family: 'Maple Mono', px: 200, bold: true, tracking: -4, fill: 'transparent', stroke: '#7FE3F0' },
    date: { format: 'yyyy-MM-dd · dddd', caps: true, family: 'Maple Mono', px: 11, italic: false, tracking: 2.2, color: '#7FE3F0' },
    prompt: 'PASSWORD FOR SAIFUL',
    hint: '[↵] UNLOCK',
    fieldMarks: ['[', ']'],
  });
});

test('Hi-Fi: the receiver front, the machine named over a dial with a 160 px amber clock', () => {
  assert.deepEqual(lockLook(checkTokens(load('hi-fi')), 'saiful', 'macbook-m2'), {
    kind: 'receiver',
    status: { text: 'LOCKED', color: '#EBDBB2' },
    host: 'MACBOOK-M2 · STEREO RECEIVER',
    clock: { family: 'Maple Mono', px: 160, bold: false, tracking: 3.2, fill: '#FABD2F', stroke: 'transparent', glow: '#FABD2F' },
    date: { format: 'dddd · d MMMM', caps: true, family: 'Maple Mono', px: 12, italic: false, tracking: 3.6, color: '#EBDBB2' },
    prompt: 'PASSWORD FOR SAIFUL',
    hint: '↵ UNLOCK',
    fieldMarks: [],
  });
});

test('Frost: a 168 px Inter Light clock in snow over heavier frost, a glass field with an Unlock chip', () => {
  assert.deepEqual(lockLook(load('frost'), 'saiful', 'macbook-m2'), {
    kind: 'frost',
    status: { text: 'Locked', color: '#D8DEE9' },
    clock: { family: 'Inter', px: 168, bold: false, weight: 'light', tracking: -5.04, fill: '#ECEFF4', stroke: 'transparent' },
    date: { format: 'dddd, d MMMM', caps: false, family: 'Inter', px: 20, italic: false, tracking: 0, color: '#D8DEE9' },
    prompt: 'Password for saiful',
    hint: '↵ Unlock',
    dots: '#ECEFF4',
    paper: { start: 0.3, grain: 0.3, vein: 0.4 },
  });
});

test('before the theme loads, the lock still draws a white clock on black', () => {
  const look = lockLook(null, 'saiful', 'macbook-m2');
  assert.equal(look.kind, 'print');
  assert.deepEqual([look.clock.fill, look.clock.px, look.prompt], ['white', 220, 'PASSWORD FOR SAIFUL']);
});
