import { test } from 'node:test';
import assert from 'node:assert/strict';
import { lockLook } from './lock-look.mjs';
import { schemeTokens } from './colorscheme-file.mjs';

const SCHEMES = ['artboard', 'catppuccin-mocha', 'github-light', 'gruvbox-dark', 'rose-pine-dawn'];

test("rose-pine-dawn locks into Artboard's card: a 96 px bold Maple Mono clock in Dawn's ink, the date as the card's label", () => {
  assert.deepEqual(lockLook(schemeTokens('rose-pine-dawn'), 'saiful'), {
    kind: 'card',
    status: { text: 'Locked', color: '#575279' },
    clock: { family: 'Maple Mono', px: 96, bold: true, tracking: -4.8, fill: '#575279', stroke: 'transparent' },
    date: { format: 'dddd, d MMMM', caps: false, family: 'Maple Mono', px: 12, italic: false, tracking: 0, color: '#907AA9' },
    prompt: '',
    hint: 'Password for saiful · ↵ to unlock',
  });
});

test('every colorscheme locks into the same card, in its own ink', () => {
  for (const name of SCHEMES) {
    const t = schemeTokens(name);
    const look = lockLook(t, 'saiful');
    assert.equal(look.kind, 'card', name);
    assert.equal(look.clock.fill, t.color.ink, name);
  }
});

test('before the theme loads, the lock still draws the card with a white clock', () => {
  const look = lockLook(null, 'saiful');
  assert.deepEqual([look.kind, look.clock.fill, look.clock.px], ['card', 'white', 96]);
});
