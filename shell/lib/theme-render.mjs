#!/usr/bin/env node
// node shell/lib/theme-render.mjs <name>: renders themes/<name>/theme.toml into $XDG_STATE_HOME/dots/theme-out/.
import { readFileSync, writeFileSync, mkdirSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';
import { parseToml } from './toml.mjs';
import { validateTheme, renderNiri, renderFoot } from './theme.mjs';

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
const out = join(process.env.XDG_STATE_HOME || join(homedir(), '.local/state'), 'dots/theme-out');
mkdirSync(out, { recursive: true });
const files = { 'shell.json': JSON.stringify(theme, null, 2) + '\n', 'niri.kdl': renderNiri(theme), 'foot.ini': renderFoot(theme) };
for (const [f, text] of Object.entries(files)) {
  const path = join(out, f);
  // Rewriting an unchanged file would wake niri's config watcher for nothing.
  if (!existsSync(path) || readFileSync(path, 'utf8') !== text) writeFileSync(path, text);
}
