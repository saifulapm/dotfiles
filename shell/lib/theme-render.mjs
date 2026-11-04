#!/usr/bin/env node
// node shell/lib/theme-render.mjs <name>: renders themes/<name>/theme.toml into $XDG_STATE_HOME/dots/theme-out/.
import { readFileSync, existsSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { parseToml } from './toml.mjs';
import { validateTheme, qtTokens } from './theme.mjs';
import { renderOutputs } from './render-out.mjs';

const name = process.argv[2];
const file = new URL(`../../themes/${name}/theme.toml`, import.meta.url).pathname;
if (!name || !existsSync(file)) {
  console.error(`theme ${name}: no themes/${name}/theme.toml`);
  process.exit(1);
}
let theme;
try {
  theme = validateTheme(parseToml(readFileSync(file, 'utf8')));
} catch (e) {
  console.error(`theme ${name}: invalid theme.toml: ${e.message}`);
  process.exit(1);
}
// The picker's cards, Paper first, then by name, each with every token its specimen draws; a theme that fails the check gets no card.
const themes = [];
const dir = new URL('../../themes/', import.meta.url).pathname;
for (const d of readdirSync(dir).sort()) {
  try {
    const t = validateTheme(parseToml(readFileSync(join(dir, d, 'theme.toml'), 'utf8')));
    themes.push(qtTokens(t));
  } catch (e) {
    continue;
  }
}
themes.sort((a, b) => (b.name === 'paper') - (a.name === 'paper'));
renderOutputs(theme, themes, `theme ${name}`);
