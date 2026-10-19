#!/usr/bin/env node
// node shell/lib/theme-render.mjs <name>: renders themes/<name>/theme.toml into $XDG_STATE_HOME/dots/theme-out/.
import { readFileSync, writeFileSync, mkdirSync, existsSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';
import { parseToml } from './toml.mjs';
import { validateTheme, renderNiri, renderFoot, renderFootArgs, renderFootOsc } from './theme.mjs';
import { renderTmux, renderKak, renderYazi, renderFish, renderGtkCss, renderGtkSettings, renderChromium } from './apps.mjs';

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
// The switcher's cards, Paper first, then by name; a theme that fails the check gets no card.
const themes = [];
const dir = new URL('../../themes/', import.meta.url).pathname;
for (const d of readdirSync(dir).sort()) {
  try {
    const t = validateTheme(parseToml(readFileSync(join(dir, d, 'theme.toml'), 'utf8')));
    themes.push({ name: t.name, mode: t.mode, color: t.color, primitive: t.primitive, type: t.type });
  } catch {
    continue;
  }
}
themes.sort((a, b) => (b.name === 'paper') - (a.name === 'paper'));
const out = join(process.env.XDG_STATE_HOME || join(homedir(), '.local/state'), 'dots/theme-out');
mkdirSync(out, { recursive: true });
const files = {
  'shell.json': JSON.stringify(theme, null, 2) + '\n',
  'niri.kdl': renderNiri(theme),
  'foot.ini': renderFoot(theme),
  'foot.args': renderFootArgs(theme),
  'foot.osc': renderFootOsc(theme),
  'tmux.conf': renderTmux(theme),
  'dots.kak': renderKak(theme),
  'yazi-theme.toml': renderYazi(theme),
  'colors.fish': renderFish(theme),
  'gtk.css': renderGtkCss(theme),
  'gtk-settings.ini': renderGtkSettings(theme),
  'chromium.json': renderChromium(theme),
  // dots theme writes a failed switch's reason here after the fallback render; any render clears it.
  notice: '',
  'themes.json': JSON.stringify(themes, null, 2) + '\n',
};
for (const [f, text] of Object.entries(files)) {
  const path = join(out, f);
  // Rewriting an unchanged file would wake niri's config watcher for nothing.
  if (!existsSync(path) || readFileSync(path, 'utf8') !== text) writeFileSync(path, text);
}
