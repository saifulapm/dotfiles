#!/usr/bin/env node
// node shell/lib/colorscheme-render.mjs <name>: renders colorschemes/<name>.toml, worn on the one design, into $XDG_STATE_HOME/dots/theme-out/.
import { readFileSync, existsSync, readdirSync } from 'node:fs';
import { parseToml } from './toml.mjs';
import { qtTokens } from './theme.mjs';
import { validateColorscheme, designOf, DEFAULT } from './colorscheme.mjs';
import { renderOutputs } from './render-out.mjs';

const dir = new URL('../../colorschemes/', import.meta.url).pathname;
const load = (name) => designOf(validateColorscheme(parseToml(readFileSync(`${dir}${name}.toml`, 'utf8'))));

const name = process.argv[2] ?? '';
// The reason after the colon is what the island shows.
if (!/^[a-z0-9][a-z0-9_-]{0,31}$/.test(name) || !existsSync(`${dir}${name}.toml`)) {
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
