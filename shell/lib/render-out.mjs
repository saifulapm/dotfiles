// Writes every app's output for one theme into $XDG_STATE_HOME/dots/theme-out/; both renderers end here.
import { readFileSync, writeFileSync, mkdirSync, existsSync, renameSync, realpathSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { homedir } from 'node:os';
import { checkTokens, qtTokens, renderNiri, renderFoot, renderFootArgs, renderFootOsc } from './theme.mjs';
import { listLook } from './voice.mjs';
import { renderTmux, renderKak, renderHelix, renderYazi, renderFish, renderGtkCss, renderGtkSettings, renderChromiumTheme, renderNewtabManifest, renderNewtabHtml, renderNewtabCss, renderClaude, renderPi, renderAmx, renderMpv, renderMpvIpc, renderZathura, renderImv, renderKbptr } from './apps.mjs';

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

// `label` begins each error line, as `theme paper` or `colorscheme artboard`; `list` is the picker's cards.
export function renderOutputs(theme, list, label) {
  // The apps that speak in the shell's voice read the tokens as the shell does, so Hi-Fi's engraved voice draws Blueprint's words bare.
  const spoken = checkTokens(theme);
  // The default state dir is the live desktop's: only the checkout its shell runs from may write there, so a worktree's render cannot rewrite it.
  if (!process.env.XDG_STATE_HOME) {
    const link = join(process.env.XDG_CONFIG_HOME || join(homedir(), '.config'), 'quickshell');
    const live = existsSync(link) ? realpathSync(link) : null;
    const own = realpathSync(new URL('..', import.meta.url).pathname);
    if (live && live !== own) {
      console.error(`${label}: the live shell runs from ${live}, not ${own}; set XDG_STATE_HOME to render elsewhere`);
      process.exit(1);
    }
  }
  const out = join(process.env.XDG_STATE_HOME || join(homedir(), '.local/state'), 'dots/theme-out');
  mkdirSync(out, { recursive: true });
  const files = {
    'shell.json': JSON.stringify(qtTokens(theme), null, 2) + '\n',
    'niri.kdl': renderNiri(theme),
    'foot.ini': renderFoot(theme),
    'foot.args': renderFootArgs(theme),
    'foot.osc': renderFootOsc(theme),
    'tmux.conf': renderTmux(spoken),
    'dots.kak': renderKak(theme) + renderMailKak(spoken),
    'helix.toml': renderHelix(theme),
    'yazi-theme.toml': renderYazi(theme),
    'colors.fish': renderFish(theme),
    'gtk.css': renderGtkCss(theme),
    'gtk-settings.ini': renderGtkSettings(theme),
    'chromium-theme/manifest.json': renderChromiumTheme(theme),
    'chromium-newtab/manifest.json': renderNewtabManifest(),
    'chromium-newtab/newtab.html': renderNewtabHtml(spoken),
    'chromium-newtab/theme.css': renderNewtabCss(theme),
    'chromium-newtab/newtab.css': readFileSync(new URL('../newtab/newtab.css', import.meta.url), 'utf8'),
    'chromium-newtab/newtab.js': readFileSync(new URL('../newtab/newtab.js', import.meta.url), 'utf8'),
    'chromium-newtab/bg.js': readFileSync(new URL('../newtab/bg.js', import.meta.url), 'utf8'),
    'chromium-newtab/words.mjs': readFileSync(new URL('./newtab.mjs', import.meta.url), 'utf8'),
    'mpv.conf': renderMpv(theme),
    'mpv.ipc': renderMpvIpc(theme),
    zathura: renderZathura(theme),
    'imv.conf': renderImv(theme),
    'wl-kbptr': renderKbptr(theme),
    'claude.json': renderClaude(theme),
    'pi.json': renderPi(theme),
    'amx.toml': renderAmx(theme),
    // dots colorscheme writes a failed switch's reason here and keeps the scheme it had; any render clears it.
    notice: '',
    'themes.json': JSON.stringify(list, null, 2) + '\n',
  };
  for (const [f, text] of Object.entries(files)) {
    const path = join(out, f);
    // Rewriting an unchanged file would wake niri's config watcher for nothing; a changed one is renamed in whole, so a reader never sees half of it.
    if (existsSync(path) && readFileSync(path, 'utf8') === text) continue;
    mkdirSync(dirname(path), { recursive: true });
    writeFileSync(path + '.tmp', text);
    renameSync(path + '.tmp', path);
  }
}
