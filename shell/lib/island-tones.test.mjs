import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { parseToml } from './toml.mjs';
import { contrast } from './theme.mjs';
import { islandFill, islandTones } from './island-tones.mjs';

const repo = new URL('../..', import.meta.url).pathname;
const names = readdirSync(join(repo, 'colorschemes')).filter((f) => f.endsWith('.toml')).map((f) => f.slice(0, -5));
const tokensOf = (name) => {
  const doc = parseToml(readFileSync(join(repo, 'colorschemes', `${name}.toml`), 'utf8'));
  return { mode: doc.meta.variant, color: doc.color };
};
const ROLES = ['muted', 'accent', 'danger', 'ok'];

// Hex to OKLCH written out here so the hue check does not lean on the module's own maths.
function oklch(hex) {
  const lin = (i) => { const v = parseInt(hex.slice(1 + i * 2, 3 + i * 2), 16) / 255; return v <= 0.04045 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4); };
  const [r, g, b] = [lin(0), lin(1), lin(2)];
  const l = Math.cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b);
  const m = Math.cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b);
  const s = Math.cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b);
  const L = 0.2104542553 * l + 0.793617785 * m - 0.0040720468 * s;
  const a = 1.9779984951 * l - 2.428592205 * m + 0.4505937099 * s;
  const bb = 0.0259040371 * l + 0.7827717662 * m - 0.808675766 * s;
  return { L, C: Math.hypot(a, bb), h: (Math.atan2(bb, a) * 180) / Math.PI };
}

test('forty colorschemes are under test', () => {
  assert.equal(names.length, 40);
});

test('the island fill is the ink on a light scheme and the surface on a dark one', () => {
  assert.equal(islandFill(tokensOf('github-light')), '#1F2328');
  assert.equal(islandFill(tokensOf('catppuccin-mocha')), '#1E1E2E');
});

for (const name of names) {
  test(`${name}: every tone reads at 4.5:1 on the fill, one that already did is untouched, a lifted one keeps its hue`, () => {
    const tokens = tokensOf(name);
    const fill = islandFill(tokens);
    const tones = islandTones(tokens);
    for (const role of ROLES) {
      const was = tokens.color[role];
      const got = tones[role];
      assert.match(got, /^#[0-9A-F]{6}$/, `${name} ${role} format`);
      assert.ok(contrast(got, fill) >= 4.5, `${name} ${role} ${got} on ${fill}`);
      if (contrast(was, fill) >= 4.5) {
        assert.equal(got, was.toUpperCase(), `${name} ${role} unchanged`);
      } else {
        const a = oklch(was);
        const b = oklch(got);
        assert.ok(b.L > a.L, `${name} ${role} lifted`);
        const dh = Math.abs(((b.h - a.h + 540) % 360) - 180);
        assert.ok(a.C < 0.02 || dh < 3, `${name} ${role} hue moved ${dh}`);
      }
    }
  });
}
