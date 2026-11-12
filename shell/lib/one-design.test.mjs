import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readdirSync, readFileSync, statSync } from 'node:fs';
import { join, relative } from 'node:path';

// Behaviour 3 of m80: nothing in the shell, the bin scripts or the tests names a deleted design, and no shell file asks niri to soften what lies behind it; the words are built from parts, so this file never matches its own scan; the two spellings of one design must stand alone, so a package name such as asahi-fix27 is not read as one; the names as the designs spelled them are read too, but not ALSA's HiFi or niri's BracketLeft.
const WORDS = new RegExp(['hard-' + 'offset', 'engr' + 'aved', 'brack' + 'et', 'brus' + 'hed', 'fro' + 'st', '(?<![a-z])hi-?' + 'fi(?![a-z])', 'gl' + 'ow', 'typew' + 'riter', 'Hard-' + 'Offset', 'Engr' + 'aved', '\\bBrack' + 'et\\b', 'Brus' + 'hed', 'Fro' + 'st', 'Hi-' + '[Ff]i', 'Gl' + 'ow', 'Typew' + 'riter'].join('|'));
const BLUR = new RegExp('bl' + 'ur');
// The emoji names (a star that shines) and the markdown pager the installs carry are words, not designs.
const ALLOWED = [/shell\/data\/emoji\.json$/];
const PAGER = new RegExp(`'${'gl' + 'ow'}'|${'gl' + 'ow'} --version`);

const root = new URL('../..', import.meta.url).pathname;
const walk = (dir) => readdirSync(dir).flatMap((f) => {
  const p = join(dir, f);
  if (statSync(p).isDirectory()) return f === 'node_modules' || f === '.git' ? [] : walk(p);
  return [p];
});
const text = (p) => {
  const b = readFileSync(p);
  return b.includes(0) ? '' : b.toString('utf8');
};

test('a deleted design is found as a word of its own, and not inside a package name', () => {
  const name = 'hi-' + 'fi';
  assert.equal(WORDS.test(`the ${name} design`), true);
  assert.equal(WORDS.test(`'${name}'`), true);
  assert.equal(WORDS.test(`${name.replace('-', '')}Card`), true);
  assert.equal(WORDS.test(`dnf install asa${name}x27`), false);
  assert.equal(WORDS.test(`// ${'Hi-' + 'Fi'}'s row lamp`), true);
  assert.equal(WORDS.test(`the ${'Fro' + 'st'} glass`), true);
  assert.equal(WORDS.test(`the ${'Brack' + 'et'} corners`), true);
  assert.equal(WORDS.test("ALSA's HiFi profile"), false);
  assert.equal(WORDS.test("['Mod+BracketLeft', 'consume-or-expel-window-left']"), false);
});

test('no file in shell, bin or tests names a deleted design', () => {
  const found = [];
  for (const p of ['shell', 'bin', 'tests'].flatMap((d) => walk(join(root, d)))) {
    if (ALLOWED.some((a) => a.test(p))) continue;
    text(p).split('\n').forEach((l, i) => {
      if (WORDS.test(l) && !PAGER.test(l)) found.push(`${relative(root, p)}:${i + 1}`);
    });
  }
  assert.deepEqual(found, []);
});

test('no shell QML file or shared module asks for a softened background', () => {
  const dirs = [join(root, 'shell'), join(root, 'shell/lib')];
  const files = dirs.flatMap((d) => readdirSync(d).filter((f) => f.endsWith('.qml') || f.endsWith('.mjs')).map((f) => join(d, f)));
  assert.deepEqual(files.filter((p) => BLUR.test(text(p))).map((p) => relative(root, p)), []);
});

test('the old themes folder is gone', () => {
  assert.equal(existsSync(join(root, 'themes')), false);
});
