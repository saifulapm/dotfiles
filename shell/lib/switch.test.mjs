import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync } from 'node:fs';
import { SWITCH, switchKind, fadeAt } from './switch.mjs';
import { schemeTokens, SCHEMES } from './colorscheme-file.mjs';

const schemes = readdirSync(SCHEMES).filter((f) => f.endsWith('.toml')).map((f) => schemeTokens(f.slice(0, -5)));

test('every pair of schemes switches by the one crossfade', () => {
  assert.ok(schemes.length >= 5);
  for (const a of schemes) for (const b of schemes) if (a !== b) assert.equal(switchKind(a, b), 'fade', `${a.name} to ${b.name}`);
});

test('the crossfade is 260 ms, a frame inside the 280 ms budget', () => {
  assert.equal(SWITCH.ms, 260);
});

test("the crossfade runs the spring's ease up to its first reach of 1, so it never overshoots and is part way at half time", () => {
  assert.equal(fadeAt(0), 0);
  assert.equal(fadeAt(1), 1);
  let last = 0;
  for (let i = 1; i <= 100; i++) {
    const v = fadeAt(i / 100);
    assert.ok(v >= last && v <= 1, `at ${i}%: ${v}`);
    last = v;
  }
  assert.ok(fadeAt(0.5) > 0.5 && fadeAt(0.5) < 0.7, `half way: ${fadeAt(0.5)}`);
});
