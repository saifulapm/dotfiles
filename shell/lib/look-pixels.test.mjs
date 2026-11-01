import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';

// A look check that reads only the shell's state passed while the text drew in its own fill (m71) and cream on cream (m73), so each theme step must also read the screen.
const dir = new URL('../../tests/dev/', import.meta.url).pathname;
const THEMES = 'paper|artboard|blueprint|hi-fi';

// The functions a script defines, each with its whole body: a one-liner, or the lines up to the closing brace at the start of a line.
function functions(lines) {
  const fns = {};
  for (let i = 0; i < lines.length; i++) {
    const m = lines[i].match(/^([a-z_][a-z0-9_]*)\(\)\s*\{/);
    if (!m) continue;
    let end = i;
    if (!/\}\s*$/.test(lines[i]) || /\{\s*$/.test(lines[i])) while (end < lines.length - 1 && !/^\}/.test(lines[end])) end++;
    fns[m[1]] = lines.slice(i, end + 1).join('\n');
  }
  return fns;
}

const calls = (text, names) => names.some((n) => new RegExp(`(^|[\\s$(;|&])${n}(\\s|$|\\))`, 'm').test(text));

// Each step from a switch to a named theme up to the next switch that runs a check, as file:theme, with whether it reads pixels.
function steps(file) {
  const lib = functions(readFileSync(dir + 'lib.sh', 'utf8').split('\n'));
  const lines = readFileSync(dir + file, 'utf8').split('\n');
  const fns = Object.assign({}, lib, functions(lines));
  const names = Object.keys(fns);
  // A pixel helper calls grim itself or through another helper.
  const pixel = new Set();
  for (let grew = true; grew; ) {
    grew = false;
    for (const n of names) if (!pixel.has(n) && (/\bgrim\b/.test(fns[n]) || calls(fns[n], [...pixel]))) grew = !!pixel.add(n);
  }
  // A switcher renders or switches to its first argument.
  const switchers = names.filter((n) => /(bin\/dots"? theme|theme-render\.mjs"?|status_theme) "\$1"/.test(fns[n]) && n !== 'status_theme');
  const switchAt = new RegExp(`^\\s*(${['"\\$repo/bin/dots" theme', 'until_ok \\d+ status_theme', ...switchers].join('|')})\\s+("?)(${THEMES}|\\S+)\\2(\\s|$)`);
  const found = [];
  let cur = null;
  lines.forEach((line) => {
    if (/^\s*#/.test(line) || /^[a-z_][a-z0-9_]*\(\)\s*\{/.test(line)) return;
    const m = line.match(switchAt);
    if (m) {
      // A switch and its wait for the same theme are one step.
      if (cur && cur.step === `${file}:${m[3]}`) return;
      cur = new RegExp(`^(${THEMES})$`).test(m[3]) && !/^\s/.test(line) ? { step: `${file}:${m[3]}`, pixels: false } : null;
      if (cur) found.push(cur);
      return;
    }
    if (cur && (/\bgrim\b/.test(line) || calls(line, [...pixel]))) cur.pixels = true;
    if (cur && /^\s*check\s/.test(line)) cur.checks = true;
  });
  // A step that checks nothing, such as the switch back to Paper at the end, has nothing to read.
  return found.filter((s) => s.checks);
}

const checks = () => readdirSync(dir).filter((f) => /-(look|voice)\.sh$/.test(f)).sort();

// The steps that read no pixels when the lint landed (ruling YCWS2MGM): this list only shrinks.
const OLD = [
  'cheatsheet-look.sh:hi-fi',
  'cheatsheet-look.sh:paper',
  'control-look.sh:hi-fi',
  'file-picker-look.sh:hi-fi',
  'files-look.sh:paper',
  'island-voice.sh:paper',
  'launcher-look.sh:artboard',
  'launcher-look.sh:hi-fi',
  'lock-look.sh:hi-fi',
  'lock-look.sh:paper',
  'margins-voice.sh:artboard',
  'margins-voice.sh:blueprint',
  'margins-voice.sh:blueprint',
  'margins-voice.sh:paper',
  'notifcentre-look.sh:hi-fi',
  'picker-look.sh:blueprint',
  'picker-look.sh:blueprint',
  'picker-look.sh:hi-fi',
  'urgency-voice.sh:artboard',
  'urgency-voice.sh:blueprint',
  'urgency-voice.sh:paper',
];

test('every theme step of a tests/dev look or voice check reads the screen, past the old ones', () => {
  const bare = checks()
    .flatMap(steps)
    .filter((s) => !s.pixels)
    .map((s) => s.step)
    .sort();
  assert.deepEqual(bare, OLD);
});

test('the step reader finds steps in every look and voice check', () => {
  for (const f of checks()) assert.ok(steps(f).length > 0, `${f} has no theme step the lint can read`);
});
