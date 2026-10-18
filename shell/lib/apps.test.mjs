import { test } from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { readFileSync, readdirSync, mkdtempSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { parseToml } from './toml.mjs';
import { validateTheme } from './theme.mjs';
import { renderTmux, renderKak, renderYazi, renderFish, renderGtkCss, renderGtkSettings, renderChromium } from './apps.mjs';

const load = (name) => validateTheme(parseToml(readFileSync(new URL(`../../themes/${name}/theme.toml`, import.meta.url), 'utf8')));
const blueprint = load('blueprint');
const paper = load('paper');

test('tmux status line takes the theme colours, lower-case', () => {
  assert.match(renderTmux(blueprint), /^set -g status-style "fg=#d6f4f8,bg=#0a1526"$/m);
  assert.match(renderTmux(paper), /^set -g status-style "fg=#[0-9a-f]{6},bg=#[0-9a-f]{6}"$/m);
  assert.doesNotMatch(renderTmux(paper), /status-style "fg=#d6f4f8/);
});

test('a throwaway tmux server accepts the fragment', (t) => {
  const dir = mkdtempSync(join(tmpdir(), 'dots-t5-'));
  const sock = `dots-t5-${process.pid}`;
  const tmux = (...a) => execFileSync('tmux', ['-L', sock, ...a], { encoding: 'utf8' });
  t.after(() => {
    try { tmux('kill-server'); } catch {}
    rmSync(dir, { recursive: true, force: true });
  });
  writeFileSync(join(dir, 'tmux.conf'), renderTmux(blueprint));
  execFileSync('tmux', ['-L', sock, '-f', '/dev/null', 'new-session', '-d']);
  tmux('source-file', join(dir, 'tmux.conf'));
  assert.match(tmux('show', '-g', 'status-style'), /#d6f4f8/);
});

test('kakoune colorscheme defines the core faces from the tokens', () => {
  const kak = renderKak(blueprint);
  assert.match(kak, /^face global Default rgb:d6f4f8,rgb:0a1526$/m);
  assert.match(kak, /^face global PrimarySelection rgb:0a1526,rgb:7fe3f0\+fg$/m);
  assert.match(kak, /^face global StatusLine rgb:d6f4f8,rgb:2e5a72$/m);
});

test('gtk.css defines the window and accent colours', () => {
  const css = renderGtkCss(blueprint);
  assert.match(css, /^@define-color window_bg_color #0c1a2e;$/m);
  assert.match(css, /^@define-color window_fg_color #d6f4f8;$/m);
  assert.match(css, /^@define-color accent_bg_color #7fe3f0;$/m);
});

test('gtk settings prefer dark exactly for dark mode', () => {
  assert.match(renderGtkSettings(blueprint), /^\[Settings\]\ngtk-application-prefer-dark-theme=true$/m);
  assert.match(renderGtkSettings(paper), /^gtk-application-prefer-dark-theme=false$/m);
});

test('chromium policy holds the surface colour and the mode', () => {
  assert.deepEqual(JSON.parse(renderChromium(blueprint)), { BrowserThemeColor: '#0a1526', BrowserColorScheme: 'dark' });
  assert.equal(JSON.parse(renderChromium(paper)).BrowserColorScheme, 'light');
});

test('colors.fish sets fish and fzf colours', () => {
  const fish = renderFish(blueprint);
  assert.match(fish, /^set -g fish_color_normal d6f4f8$/m);
  assert.match(fish, /^set -gx FZF_DEFAULT_OPTS "--color=fg:#d6f4f8,bg:#0a1526,hl:#7fe3f0/m);
});

test('yazi theme sets the keys yazi 26.9 reads', () => {
  const y = renderYazi(blueprint);
  assert.match(y, /^\[mgr\]$/m);
  assert.match(y, /^cwd = \{ fg = "cyan" \}$/m);
  assert.match(y, /^hovered = \{ fg = "#0a1526", bg = "cyan" \}$/m);
  assert.match(y, /^\[mode\]$/m);
  assert.match(y, /^\[status\]$/m);
  assert.match(y, /^border_style = \{ fg = "darkgray" \}$/m);
  // Named colours follow the terminal palette, so a running yazi recolours live.
  const named = y.match(/"[a-z]+"/g).length;
  const hex = y.match(/"#[0-9a-f]{6}"/g).length;
  assert.ok(named > hex, `${named} named vs ${hex} hex`);
});

test('no path under home/ mentions kitty, and the links point at theme-out', () => {
  const home = new URL('../../home/', import.meta.url).pathname;
  const walk = (d) => readdirSync(d, { withFileTypes: true }).flatMap((e) => (e.isDirectory() ? walk(join(d, e.name)) : [join(d, e.name)]));
  const files = walk(home);
  assert.deepEqual(files.filter((f) => /kitty/i.test(f)), []);
  const links = files.filter((f) => /\/symlink_(dots\.kak|theme\.toml|gtk\.css|settings\.ini)/.test(f));
  assert.equal(links.length, 6);
  for (const l of links) assert.match(readFileSync(l, 'utf8'), /\.local\/state\/dots\/theme-out\/(dots\.kak|yazi-theme\.toml|gtk\.css|gtk-settings\.ini)\s*$/, l);
});
