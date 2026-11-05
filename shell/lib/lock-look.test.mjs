import { test } from 'node:test';
import assert from 'node:assert/strict';
import { lockLook } from './lock-look.mjs';
import { contrast } from './theme.mjs';
import { schemeTokens, schemeNames } from './colorscheme-file.mjs';

const SCHEMES = schemeNames();

test('rose-pine-dawn locks onto its bare surface: a 120 px bold Maple Mono clock in ink, a quiet date, the passage smaller than the paper\'s and centred', () => {
  assert.deepEqual(lockLook(schemeTokens('rose-pine-dawn'), 'saiful'), {
    kind: 'open',
    ground: '#FAF4ED',
    clock: { family: 'Maple Mono', px: 120, bold: true, tracking: -6, fill: '#575279', stroke: 'transparent' },
    date: { format: 'dddd, d MMMM', caps: false, family: 'Maple Mono', px: 15, italic: false, tracking: 0, color: '#716D8B' },
    passage: {
      width: 720,
      gap: 18,
      label: { font: 'Maple Mono', size: 13, color: '#7D6795' },
      ar: { size: 46, color: '#575279' },
      pron: { font: 'Noto Sans Bengali', size: 17, height: 1.6, color: '#716D8B' },
      bn: { font: 'Noto Sans Bengali', size: 21, height: 1.6, color: '#575279' },
      en: { font: 'Maple Mono', size: 20, height: 1.55, color: '#575279' },
      ref: { font: 'Maple Mono', size: 14, color: '#716D8B' },
      bnRef: { font: 'Noto Sans Bengali', size: 15 },
    },
    prompt: '',
    hint: 'Password for saiful · ↵ to unlock',
  });
});

test('every colorscheme locks onto its own surface, the clock in its ink and every line reading at 4.5:1', () => {
  for (const name of SCHEMES) {
    const t = schemeTokens(name);
    const look = lockLook(t, 'saiful');
    assert.equal(look.kind, 'open', name);
    assert.equal(look.ground, t.color.surface, name);
    assert.equal(look.clock.fill, t.color.ink, name);
    for (const [what, color] of [['ink', t.color.ink], ['date', look.date.color], ['label', look.passage.label.color], ['pron', look.passage.pron.color], ['ref', look.passage.ref.color]])
      assert.ok(contrast(color, look.ground) >= 4.5, `${name} ${what} ${color}: ${contrast(color, look.ground).toFixed(2)}`);
  }
});

test('before the theme loads, the lock still draws its clock in white on black', () => {
  const look = lockLook(null, 'saiful');
  assert.deepEqual([look.kind, look.ground, look.clock.fill, look.clock.px], ['open', 'black', 'white', 120]);
});
