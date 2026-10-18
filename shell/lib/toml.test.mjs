import { test } from 'node:test';
import assert from 'node:assert/strict';
import { parseToml } from './toml.mjs';

test('reads tables, strings, numbers, bools and string arrays', () => {
  const doc = parseToml(`
# a comment
top = "x"
[meta]
name = "paper"   # trailing comment
[niri]
gaps = 24
scale = 1.25
blur = false
[color]
ansi = [
  "#000000", "#ffffff",
]
`);
  assert.deepEqual(doc, {
    top: 'x',
    meta: { name: 'paper' },
    niri: { gaps: 24, scale: 1.25, blur: false },
    color: { ansi: ['#000000', '#ffffff'] },
  });
});

test('names the line it cannot read', () => {
  assert.throws(() => parseToml('[meta]\nname = paper\n'), /line 2/);
});
