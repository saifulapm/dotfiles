#!/usr/bin/env node
// node shell/lib/theme-render.mjs <name>: renders themes/<name>/theme.toml into $XDG_STATE_HOME/dots/theme-out/.
import { readFileSync, writeFileSync, mkdirSync, existsSync, readdirSync, renameSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { homedir } from 'node:os';
import { parseToml } from './toml.mjs';
import { validateTheme, renderNiri, renderFoot, renderFootArgs, renderFootOsc } from './theme.mjs';
import { listLook } from './voice.mjs';
import { renderTmux, renderKak, renderHelix, renderYazi, renderFish, renderGtkCss, renderGtkSettings, renderChromiumTheme, renderClaude, renderPi, renderAmx, renderMpv, renderMpvIpc } from './apps.mjs';

// Board hexes for the kak-mail list that no token carries: Paper's sender blue, Artboard's date orange.
const MAIL_BOARD = { paper: { sender: '#2C4A9A' }, artboard: { date: '#C2410C' } };
const rgb = (s) => `rgb:${s.toLowerCase().slice(1)}`;

// The kak-mail list's faces and key strip, which dots.kak carries so a `colorscheme dots` recolours an open list.
function renderMailKak(t) {
  const c = t.color;
  const look = listLook(t);
  const board = MAIL_BOARD[t.name] ?? {};
  const strip = [['↵', 'open'], ['r', 'reply'], ['e', 'archive'], ['s', 'screener'], ['f', 'feed'], ['?', 'help']];
  const keys = look.keys(strip).map((k) => `{MailKey}${k.key}{MailStrip} ${k.word}`).join(' · ');
  const key = look.voice === 'bracket' ? c.accent : c.ink;
  const faces = [
    ['MailDate', rgb(board.date ?? c.muted)],
    ['MailSender', rgb(board.sender ?? c.accent)],
    ['MailSubject', rgb(c.ink)],
    ['MailUnread', 'default,default+b'],
    ['MailCursor', `${rgb(look.cursor.text)},${rgb(look.cursor.fill)}+b`],
    ['MailStrip', `${rgb(c.muted)},${rgb(c.surface)}`],
    ['MailKey', `${rgb(key)},${rgb(c.surface)}${look.voice === 'caps' ? '+b' : ''}`],
  ];
  return faces.map(([n, v]) => `face global ${n} ${v}`).join('\n') + `\nset-option global mail_keys '${keys}'\ntry mail-strip-all\n`;
}

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
    themes.push(t);
  } catch (e) {
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
  'dots.kak': renderKak(theme) + renderMailKak(theme),
  'helix.toml': renderHelix(theme),
  'yazi-theme.toml': renderYazi(theme),
  'colors.fish': renderFish(theme),
  'gtk.css': renderGtkCss(theme),
  'gtk-settings.ini': renderGtkSettings(theme),
  'chromium-theme/manifest.json': renderChromiumTheme(theme),
  'mpv.conf': renderMpv(theme),
  'mpv.ipc': renderMpvIpc(theme),
  'claude.json': renderClaude(theme),
  'pi.json': renderPi(theme),
  'amx.toml': renderAmx(theme),
  // dots theme writes a failed switch's reason here after the fallback render; any render clears it.
  notice: '',
  'themes.json': JSON.stringify(themes, null, 2) + '\n',
};
for (const [f, text] of Object.entries(files)) {
  const path = join(out, f);
  // Rewriting an unchanged file would wake niri's config watcher for nothing; a changed one is renamed in whole, so a reader never sees half of it.
  if (existsSync(path) && readFileSync(path, 'utf8') === text) continue;
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path + '.tmp', text);
  renameSync(path + '.tmp', path);
}
