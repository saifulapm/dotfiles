import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { parseToml } from './toml.mjs';
import { validateColorscheme, designOf } from './colorscheme.mjs';
import { validateTheme, renderNiri } from './theme.mjs';

const read = (name) => parseToml(readFileSync(new URL(`../../colorschemes/${name}.toml`, import.meta.url), 'utf8'));
const artboard = () => read('artboard');

test('artboard keeps the exact colours of the artboard theme', () => {
  const s = validateColorscheme(artboard());
  const theme = parseToml(readFileSync(new URL('../../themes/artboard/theme.toml', import.meta.url), 'utf8'));
  assert.deepEqual(s.color, theme.color);
  assert.deepEqual(s.syntax, theme.syntax);
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
  assert.deepEqual(t.primitive, { paper: 'dots', frame: 'ink', shadow: 'none', corner: 'square', motion: 'spring' });
  assert.deepEqual(t.paper, { spacing: 16, dot: '#D0D7DE' });
  assert.deepEqual(t.type, { display: 'Maple Mono', ui: 'Maple Mono', mono: 'Maple Mono', voice: 'plain', scale: 1 });
  assert.equal(t.mode, 'light');
  assert.equal(t.name, 'artboard');
  assert.equal(t.color.glass, t.color.surface);
  // The shell checks shell.json against the theme check, so the design must pass it as it stands.
  assert.doesNotThrow(() => validateTheme(Object.assign({}, t, { meta: { name: t.name, mode: t.mode } })));
});

test('niri frames the focused window in ink and the rest in line, 1 px, square, with no ring and no shadow', () => {
  const kdl = renderNiri(designOf(validateColorscheme(artboard())));
  assert.match(kdl, /border \{\n\s+on\n\s+width 1\n\s+active-color "#15171B"\n\s+inactive-color "#D0D7DE"\n\s+\}/);
  assert.match(kdl, /focus-ring \{\n\s+off\n\s+\}/);
  assert.match(kdl, /shadow \{\n\s+off\n\s+\}/);
  assert.match(kdl, /geometry-corner-radius 0\n/);
  assert.match(kdl, /gaps 28\n/);
  assert.match(kdl, /background-color "#E4E6EA"/);
  assert.match(kdl, /spring damping-ratio=0\.72 stiffness=380/);
});
