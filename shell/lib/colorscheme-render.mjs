#!/usr/bin/env node
// node shell/lib/colorscheme-render.mjs <name>|--saved: renders colorschemes/<name>.toml, worn on the one design, into $XDG_STATE_HOME/dots/theme-out/.
import { readFileSync, writeFileSync, mkdirSync, existsSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';
import { qtTokens } from './theme.mjs';
import { DEFAULT } from './colorscheme.mjs';
import { SCHEMES as dir, loadScheme as load } from './colorscheme-file.mjs';
import { renderOutputs } from './render-out.mjs';


const valid = (n) => /^[a-z0-9][a-z0-9_-]{0,31}$/.test(n) && existsSync(`${dir}${n}.toml`);
// --saved renders the saved name; one that is no colorscheme (an old theme name, or none) becomes the default and is saved after the render.
const state = join(process.env.XDG_STATE_HOME || join(homedir(), '.local/state'), 'dots');
const asked = process.argv[2] === '--saved';
let name = process.argv[2] ?? '';
let remap = false;
if (asked) {
  const file = join(state, 'theme');
  name = existsSync(file) ? readFileSync(file, 'utf8').trim() : '';
  remap = !valid(name);
  if (remap) name = DEFAULT;
}
// The reason after the colon is what the island shows.
if (!valid(name)) {
  console.error(`colorscheme ${name}: no such colorscheme`);
  process.exit(1);
}
let theme;
try {
  theme = load(name);
} catch (e) {
  console.error(`colorscheme ${name}: ${e.message.replace(/^colorscheme: /, '')}`);
  process.exit(1);
}
// The picker's cards, the default first, then by name; a scheme that fails the check gets no card.
const list = [];
for (const f of readdirSync(dir).filter((f) => f.endsWith('.toml')).sort()) {
  try {
    list.push(qtTokens(load(f.slice(0, -5))));
  } catch (e) {
    continue;
  }
}
list.sort((a, b) => (b.name === DEFAULT) - (a.name === DEFAULT));
renderOutputs(theme, list, `colorscheme ${name}`);
if (remap) {
  mkdirSync(state, { recursive: true, mode: 0o700 });
  writeFileSync(join(state, 'theme'), `${name}\n`);
}
