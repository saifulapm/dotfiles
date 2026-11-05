import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { parseToml } from './toml.mjs';
import { validateColorscheme, designOf } from './colorscheme.mjs';
import { validateTheme, renderNiri, contrast } from './theme.mjs';

const read = (name) => parseToml(readFileSync(new URL(`../../colorschemes/${name}.toml`, import.meta.url), 'utf8'));
const artboard = () => read('artboard');

test('artboard keeps the exact colours of the old artboard theme', () => {
  const s = validateColorscheme(artboard());
  assert.deepEqual([s.color.paper, s.color.surface, s.color.ink, s.color.muted, s.color.line, s.color.accent], ['#E4E6EA', '#FFFFFF', '#15171B', '#57606A', '#D0D7DE', '#3D5AFE']);
  assert.equal(s.variant, 'light');
  assert.equal(s.title, 'Artboard');
});

for (const key of ['primitive', 'type', 'niri', 'paper']) {
  test(`a colorscheme holding a [${key}] key is refused, naming the key`, () => {
    const doc = Object.assign(artboard(), { [key]: { gaps: 4 } });
    assert.throws(() => validateColorscheme(doc), new RegExp(`\\b${key}\\b`));
  });
}

test('a colour key no colorscheme has is refused, naming it', () => {
  const doc = artboard();
  doc.color.glass = '#FFFFFF';
  assert.throws(() => validateColorscheme(doc), /color\.glass/);
});

test('a variant that is not light or dark is refused', () => {
  const doc = artboard();
  doc.meta.variant = 'dim';
  assert.throws(() => validateColorscheme(doc), /meta\.variant/);
});

test('ink on surface under 4.5:1 is refused with contrast in the message', () => {
  const doc = artboard();
  doc.color.ink = '#9AA0A6';
  assert.throws(() => validateColorscheme(doc), /contrast/);
});

test('every scheme wears the one design: dots in line, square, ink frame, no shadow, Maple Mono, plain, spring', () => {
  const t = designOf(validateColorscheme(artboard()));
  assert.deepEqual(t.primitive, { paper: 'dots', frame: 'line', shadow: 'none', corner: 'square', motion: 'spring' });
  assert.deepEqual(t.paper, { spacing: 16, dot: '#D0D7DE' });
  assert.deepEqual(t.type, { display: 'Maple Mono', ui: 'Maple Mono', mono: 'Maple Mono', voice: 'plain', scale: 1 });
  assert.equal(t.mode, 'light');
  assert.equal(t.name, 'artboard');
  // The shell checks shell.json against the theme check, so the design must pass it as it stands.
  assert.doesNotThrow(() => validateTheme(Object.assign({}, t, { meta: { name: t.name, mode: t.mode } })));
});

test('niri frames every window in line, focused or not, 1 px, square, with no ring and no shadow', () => {
  const kdl = renderNiri(designOf(validateColorscheme(artboard())));
  assert.match(kdl, /border \{\n\s+on\n\s+width 1\n\s+active-color "#D0D7DE"\n\s+inactive-color "#D0D7DE"\n\s+\}/);
  assert.match(kdl, /focus-ring \{\n\s+off\n\s+\}/);
  assert.match(kdl, /shadow \{\n\s+off\n\s+\}/);
  assert.match(kdl, /geometry-corner-radius 0\n/);
  assert.match(kdl, /gaps 28\n/);
  assert.match(kdl, /background-color "#E4E6EA"/);
  assert.match(kdl, /spring damping-ratio=0\.72 stiffness=380/);
});

test('a text colour under 4.5:1 on surface, a comment or ANSI hue under 3:1, or ink under 4.5:1 on line is refused, naming it', () => {
  for (const [section, k, v] of [['color', 'muted', '#C0C4CA'], ['color', 'accent', '#B0C0FF'], ['syntax', 'string', '#C8D0D8'], ['syntax', 'comment', '#E0E2E6']]) {
    const doc = artboard();
    doc[section][k] = v;
    assert.throws(() => validateColorscheme(doc), new RegExp(`${section}\\.${k}.*contrast`), k);
  }
  const hue = artboard();
  hue.color.ansi[3] = '#F0E0A0';
  assert.throws(() => validateColorscheme(hue), /ansi 3.*contrast/);
  const low = artboard();
  low.color.line = '#5A6068';
  assert.throws(() => validateColorscheme(low), /ink on line.*contrast/);
});

test("every scheme's frame shows at 1.4:1 on its surface, its line where that already does", () => {
  for (const f of readdirSync(new URL('../../colorschemes/', import.meta.url)).filter((f) => f.endsWith('.toml'))) {
    const t = designOf(validateColorscheme(read(f.slice(0, -5))));
    assert.ok(contrast(t.niri.border_inactive, t.color.surface) >= 1.4, `${f} ${contrast(t.niri.border_inactive, t.color.surface)}`);
    if (contrast(t.color.line, t.color.surface) >= 1.4) assert.equal(t.niri.border_inactive, t.color.line, f);
  }
});
