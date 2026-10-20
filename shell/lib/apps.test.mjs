import { test } from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { readFileSync, readdirSync, mkdtempSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { parseToml } from './toml.mjs';
import { validateTheme } from './theme.mjs';
import { renderTmux, renderKak, renderHelix, renderYazi, renderFish, renderGtkCss, renderGtkSettings, renderChromium, renderClaude, renderPi, renderOpencode, renderAmx } from './apps.mjs';

const load = (name) => validateTheme(parseToml(readFileSync(new URL(`../../themes/${name}/theme.toml`, import.meta.url), 'utf8')));
const blueprint = load('blueprint');
const paper = load('paper');

const artboard = load('artboard');

test('tmux tabs take the theme\'s corner: round pills, cut dimension marks, square blocks', () => {
  const current = (t) => renderTmux(t).match(/^set -g window-status-current-format "(.*)"$/m)[1];
  assert.match(current(artboard), /\ue0b6.*#\[fg=#ffffff,bg=#3d5afe\].*\ue0b4/);
  assert.equal(current(blueprint), '#[fg=#7fe3f0]├─ #[fg=#d6f4f8]#I #W#{?window_zoomed_flag, \u{f0293},}#[fg=#7fe3f0] ─┤#[default]');
  // The session's marks sit in the line colour, and turn the accent while the prefix is held.
  assert.match(renderTmux(blueprint), /^set -g status-left " #\[fg=#\{\?client_prefix,#7fe3f0,#2e5a72}\]├─ /m);
  assert.doesNotMatch(current(paper), /[\ue0b4\ue0b6]/);
  assert.match(current(paper), /#\[fg=#faf6ec,bg=#c8381e\] #I #W/);
});

test('the active tmux pane border follows the frame', () => {
  assert.match(renderTmux(paper), /^set -g pane-active-border-style "fg=#1c1915"$/m);
  assert.match(renderTmux(blueprint), /^set -g pane-active-border-style "fg=#7fe3f0"$/m);
  assert.match(renderTmux(paper), /^set -g pane-border-lines single$/m);
  const double = structuredClone(paper);
  double.primitive.frame = 'double';
  assert.match(renderTmux(double), /^set -g pane-border-lines double$/m);
});

test('a throwaway tmux server accepts each theme\'s fragment', (t) => {
  const dir = mkdtempSync(join(tmpdir(), 'dots-apps-'));
  const sock = `dots-apps-${process.pid}`;
  const tmux = (...a) => execFileSync('tmux', ['-L', sock, ...a], { encoding: 'utf8' });
  t.after(() => {
    try { tmux('kill-server'); } catch {}
    rmSync(dir, { recursive: true, force: true });
  });
  execFileSync('tmux', ['-L', sock, '-f', '/dev/null', 'new-session', '-d']);
  for (const theme of [paper, artboard, blueprint]) {
    writeFileSync(join(dir, 'tmux.conf'), renderTmux(theme));
    tmux('source-file', join(dir, 'tmux.conf'));
    assert.match(tmux('show', '-g', 'status-style'), new RegExp(`fg=${theme.color.muted.toLowerCase()},bg=default`));
    // Without the prefix held, the session badge is ink.
    assert.match(tmux('display', '-p', '#{T:status-left}'), new RegExp(`fg=${theme.color.ink.toLowerCase()}`, 'i'));
  }
});

test('kakoune colorscheme defines the core faces from the tokens', () => {
  const kak = renderKak(blueprint);
  assert.match(kak, /^face global Default rgb:d6f4f8,rgb:0a1526$/m);
  assert.match(kak, /^face global PrimarySelection rgb:0a1526,rgb:7fe3f0\+fg$/m);
  assert.match(kak, /^face global StatusLine rgb:d6f4f8,rgb:0a1526$/m);
});

test('kakoune draws its status line and info flat and its menu on a 6% ink tint, keeping red for errors', () => {
  const kak = renderKak(paper);
  assert.match(kak, /^face global StatusLineInfo rgb:575653,rgb:faf6ec$/m);
  assert.match(kak, /^face global Information rgb:1c1915,rgb:faf6ec$/m);
  assert.match(kak, /^face global MenuBackground rgb:1c1915,rgb:ede9df$/m);
  assert.match(kak, /^face global Error rgb:faf6ec,rgb:c8381e$/m);
});

test('kakoune colours code from the theme\'s syntax table', () => {
  const kak = renderKak(blueprint);
  assert.match(kak, /^face global keyword rgb:c792ea\+b$/m);
  assert.match(kak, /^face global string rgb:ecc48d$/m);
  assert.match(kak, /^face global comment rgb:637777\+i$/m);
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
  assert.match(renderGtkSettings(paper), /^gtk-font-name=Maple Mono 11$/m);
});

test('chromium policy holds the surface colour and the mode', () => {
  assert.deepEqual(JSON.parse(renderChromium(blueprint)), { BrowserThemeColor: '#0a1526', BrowserColorScheme: 'dark' });
  assert.equal(JSON.parse(renderChromium(paper)).BrowserColorScheme, 'light');
});

test('colors.fish sets fish and fzf colours', () => {
  const fish = renderFish(blueprint);
  assert.match(fish, /^set -g fish_color_normal d6f4f8$/m);
  // The prompt draws the directory and a failed status in these.
  assert.match(fish, /^set -g fish_color_cwd 7fe3f0$/m);
  assert.match(fish, /^set -g fish_color_status ffb547$/m);
  assert.match(fish, /^set -gx FZF_DEFAULT_OPTS "--color=fg:#d6f4f8,bg:#0a1526,hl:#7fe3f0/m);
});

test('yazi theme sets the keys yazi 26.9 reads', () => {
  const y = renderYazi(blueprint);
  assert.match(y, /^\[mgr\]$/m);
  assert.match(y, /^cwd = \{ fg = "cyan" \}$/m);
  assert.match(y, /^hovered = \{ fg = "#0a1526", bg = "cyan" \}$/m);
  assert.match(y, /^\[mode\]$/m);
  assert.match(y, /^\[status\]$/m);
  assert.match(y, /^border_style = \{ fg = "black" \}$/m);
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

test('a running fish takes the new colours at its next prompt', (t) => {
  const state = mkdtempSync(join(tmpdir(), 'dots-fish-'));
  t.after(() => rmSync(state, { recursive: true, force: true }));
  const out = join(state, 'dots/theme-out');
  execFileSync('mkdir', ['-p', out]);
  writeFileSync(join(out, 'colors.fish'), renderFish(paper));
  const config = new URL('../../home/dot_config/fish/config.fish', import.meta.url).pathname;
  // One fish: the config at start, then a new colours file and a prompt, as after dots theme.
  const script = `source ${config}; echo $fish_color_normal; echo '${renderFish(blueprint).replace(/'/g, "\\'")}' > ${out}/colors.fish; emit fish_prompt; echo $fish_color_normal`;
  const seen = execFileSync('fish', ['--no-config', '-c', script], { env: { ...process.env, XDG_STATE_HOME: state }, encoding: 'utf8' }).trim().split('\n');
  assert.deepEqual(seen, [paper.color.ink.slice(1).toLowerCase(), 'd6f4f8']);
});

// claude, pi, opencode and amx kept v1's dark palette, so on Paper and Artboard they drew dark boxes in a light terminal.
test('the Claude Code theme starts from the light or dark preset of the theme and takes its tokens', () => {
  const a = JSON.parse(renderClaude(artboard));
  assert.equal(a.name, 'qshell');
  assert.equal(a.base, 'light');
  assert.deepEqual([a.overrides.claude, a.overrides.text, a.overrides.inverseText, a.overrides.success, a.overrides.error], ['#3d5afe', '#15171b', '#ffffff', '#1a7f37', '#cf222e']);
  assert.equal(a.overrides.diffAdded, '#ddece1');
  const b = JSON.parse(renderClaude(blueprint));
  assert.equal(b.base, 'dark');
  assert.equal(b.overrides.claude, '#7fe3f0');
});

test('the pi theme names its appearance, sits on the terminal surface, and every colour resolves to a var', () => {
  const a = JSON.parse(renderPi(artboard));
  assert.deepEqual([a.name, a.appearance, a.vars.background, a.vars.foreground, a.vars.accent], ['qshell', 'light', '#ffffff', '#15171b', '#3d5afe']);
  assert.equal(JSON.parse(renderPi(blueprint)).appearance, 'dark');
  assert.ok(Object.keys(a.colors).length >= 51, `${Object.keys(a.colors).length} colours`);
  for (const [k, v] of Object.entries(a.colors)) assert.ok(v in a.vars, `${k}: ${v}`);
});

test('the opencode theme sits on the terminal surface and every theme key resolves to a def', () => {
  const a = JSON.parse(renderOpencode(artboard));
  assert.deepEqual([a.defs.bg, a.defs.fg, a.defs.accent, a.theme.background, a.theme.text], ['#ffffff', '#15171b', '#3d5afe', 'bg', 'fg']);
  for (const [k, v] of Object.entries(a.theme)) assert.ok(v in a.defs, `${k}: ${v}`);
});

test('the amx theme sets its six roles from the tokens', () => {
  assert.equal(
    renderAmx(artboard),
    ['waiting = "#9a6700"', 'done = "#1a7f37"', 'failed = "#cf222e"', 'stopped = "#57606a"', 'accent = "#3d5afe"', 'cursor = "#d0d7de"', ''].join('\n'),
  );
});

test('helix takes the kak look: syntax colours, a flat status line, and the menu and popups on a 6% ink tint', () => {
  const hx = renderHelix(paper);
  assert.match(hx, /^"ui\.background" = \{ bg = "#faf6ec" \}$/m);
  assert.match(hx, /^"keyword" = \{ fg = "#66800b", modifiers = \["bold"\] \}$/m);
  assert.match(hx, /^"comment" = \{ fg = "#575653", modifiers = \["italic"\] \}$/m);
  assert.match(hx, /^"string" = "#24837b"$/m);
  assert.match(hx, /^"ui\.statusline" = \{ fg = "#1c1915", bg = "#faf6ec" \}$/m);
  assert.match(hx, /^"ui\.statusline\.normal" = \{ fg = "#c8381e", bg = "#faf6ec", modifiers = \["bold"\] \}$/m);
  assert.match(hx, /^"ui\.popup" = \{ fg = "#1c1915", bg = "#ede9df" \}$/m);
  assert.match(hx, /^"ui\.menu\.selected" = \{ fg = "#faf6ec", bg = "#c8381e" \}$/m);
  assert.match(hx, /^"diagnostic\.error" = \{ underline = \{ color = "#c8381e", style = "curl" \} \}$/m);
  assert.match(renderHelix(blueprint), /^"function" = "#82aaff"$/m);
});
