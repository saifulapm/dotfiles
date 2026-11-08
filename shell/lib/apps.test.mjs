import { test } from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { readFileSync, readdirSync, mkdtempSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createHash } from 'node:crypto';
import { contrast } from './theme.mjs';
import { loadScheme, schemeNames } from './colorscheme-file.mjs';
import { termTheme, renderGtk4Css, renderBtop, renderLazygit, renderTmux, renderKak, renderHelix, renderYazi, renderFish, renderGtkCss, renderGtkSettings, renderChromiumTheme, renderNewtabManifest, renderNewtabHtml, renderNewtabCss, renderClaude, renderPi, renderAmx, renderMpv, renderZathura, renderImv, renderKbptr } from './apps.mjs';

// Two schemes stand in for the old themes the checks were written against: a light one, and a dark one.
const light = loadScheme('github-light');
const dark = loadScheme('gruvbox-dark');

const artboard = loadScheme('artboard');

// The tmux bar reads as the page's running head, in the margins' words, with an accent dot before the current window.
const tmuxOpt = (t, name) => renderTmux(t).match(new RegExp(`^set -g ${name} "(.*)"$`, 'm'))[1];

test('the tmux bar draws no filled block in any theme, only text in the margin colours', () => {
  for (const t of [light, artboard, dark]) {
    for (const o of ['status-left', 'status-right', 'window-status-format', 'window-status-current-format']) {
      assert.doesNotMatch(tmuxOpt(t, o), /bg=(?!default)/, `${t.name} ${o}`);
    }
  }
});

test('tmux windows read like the margin number: an accent dot before the current window in ink, the rest muted', () => {
  for (const t of [light, dark, artboard]) {
    const c = t.color;
    assert.ok(tmuxOpt(t, 'window-status-current-format').startsWith(`#[fg=${c.accent.toLowerCase()}]● #[fg=${c.ink.toLowerCase()},bold]#{?#{e|<:#{window_index},10},0,}#{window_index}#[nobold] `), t.name);
    assert.ok(tmuxOpt(t, 'window-status-format').startsWith(`#[fg=${c.muted.toLowerCase()}]`), t.name);
    assert.doesNotMatch(tmuxOpt(t, 'window-status-current-format'), /s\/a\/A\//, t.name);
    assert.equal(tmuxOpt(t, 'window-status-separator'), `#[fg=${c.muted.toLowerCase()}]    `, t.name);
  }
});

test('the tmux session drops amx\'s prefix, turns the accent while the prefix key is held, and agents speak in the margins\' words', () => {
  assert.equal(tmuxOpt(dark, 'status-left'), ' #[fg=#{?client_prefix,#83a598,#a89984}]#{s/^amx-//;=/24/…:session_name}#[default] ');
  assert.match(tmuxOpt(artboard, 'status-right'), /^#\(dots-agents 57606a 3d5afe 15171b\)/);
  assert.match(tmuxOpt(dark, 'status-right'), /^#\(dots-agents a89984 83a598 ebdbb2\)/);
});

test("every tmux border, the active pane's too, is the quiet frame, in single lines", () => {
  for (const t of [light, dark]) {
    const frame = t.niri.border_inactive.toLowerCase();
    for (const k of ['pane-border', 'pane-active-border', 'popup-border', 'menu-border']) assert.equal(tmuxOpt(t, `${k}-style`), `fg=${frame}`, `${t.name} ${k}`);
  }
  for (const k of ['pane', 'popup', 'menu']) assert.match(renderTmux(dark), new RegExp(`^set -g ${k}-border-lines single$`, 'm'), k);
});

test('a throwaway tmux server accepts each theme\'s fragment', (t) => {
  const dir = mkdtempSync(join(tmpdir(), 'dots-apps-'));
  const sock = `dots-apps-${process.pid}`;
  const tmux = (...a) => execFileSync('tmux', ['-L', sock, ...a], { encoding: 'utf8' });
  t.after(() => {
    try { tmux('kill-server'); } catch {}
    rmSync(dir, { recursive: true, force: true });
  });
  execFileSync('tmux', ['-L', sock, '-f', '/dev/null', 'new-session', '-d', '-s', 'amx-dots']);
  for (const theme of [light, artboard, dark]) {
    writeFileSync(join(dir, 'tmux.conf'), renderTmux(theme));
    tmux('source-file', join(dir, 'tmux.conf'));
    assert.match(tmux('show', '-g', 'status-style'), new RegExp(`fg=${theme.color.muted.toLowerCase()},bg=default`));
    // Without the prefix held, the session reads in the muted colour, without amx's prefix and in the theme's case.
    const name = theme.type.voice === 'plain' ? 'dots' : 'DOTS';
    assert.equal(tmux('display', '-p', '#{T:status-left}'), ` #[fg=${theme.color.muted.toLowerCase()}]${name}#[default] \n`);
  }
});

test('kakoune colorscheme defines the core faces from the tokens', () => {
  const kak = renderKak(dark);
  assert.match(kak, /^face global Default rgb:ebdbb2,rgb:282828$/m);
  assert.match(kak, /^face global PrimarySelection rgb:282828,rgb:83a598\+fg$/m);
  assert.match(kak, /^face global StatusLine rgb:ebdbb2,rgb:282828$/m);
});

test('kakoune draws its status line and info flat and its menu on a 6% ink tint, keeping red for errors', () => {
  const kak = renderKak(light);
  assert.match(kak, /^face global StatusLineInfo rgb:59636e,rgb:ffffff$/m);
  assert.match(kak, /^face global Information rgb:1f2328,rgb:ffffff$/m);
  assert.match(kak, /^face global MenuBackground rgb:1f2328,rgb:f2f2f2$/m);
  assert.match(kak, /^face global Error rgb:ffffff,rgb:d1242f$/m);
});

test('kakoune colours code from the scheme\'s syntax table', () => {
  const kak = renderKak(dark);
  assert.match(kak, /^face global keyword rgb:ff4f39\+b$/m);
  assert.match(kak, /^face global string rgb:b8bb26$/m);
  assert.match(kak, /^face global comment rgb:928374\+i$/m);
});

test('gtk.css defines the window and accent colours', () => {
  const css = renderGtkCss(dark);
  assert.match(css, /^@define-color window_bg_color #1d2021;$/m);
  assert.match(css, /^@define-color window_fg_color #ebdbb2;$/m);
  assert.match(css, /^@define-color accent_bg_color #83a598;$/m);
});

test('gtk settings prefer dark exactly for dark mode', () => {
  assert.match(renderGtkSettings(dark), /^\[Settings\]\ngtk-application-prefer-dark-theme=true$/m);
  assert.match(renderGtkSettings(light), /^gtk-application-prefer-dark-theme=false$/m);
  assert.match(renderGtkSettings(light), /^gtk-font-name=Maple Mono 11$/m);
});

// A colour policy would block the theme extension, so the manifest alone carries the exact colours, from Chromium's next start.
test('the chromium theme extension frames the window in paper and draws the toolbar on surface', () => {
  const rgbOf = (hex) => [1, 3, 5].map((i) => parseInt(hex.slice(i, i + 2), 16));
  for (const t of [light, dark, artboard]) {
    const m = JSON.parse(renderChromiumTheme(t));
    assert.equal(m.manifest_version, 3);
    assert.deepEqual(m.theme.colors.frame, rgbOf(t.color.paper), t.name);
    assert.deepEqual(m.theme.colors.toolbar, rgbOf(t.color.surface), t.name);
    assert.deepEqual(m.theme.colors.toolbar_text, rgbOf(t.color.ink), t.name);
    assert.deepEqual(m.theme.colors.ntp_background, rgbOf(t.color.paper), t.name);
  }
  assert.deepEqual(JSON.parse(renderChromiumTheme(dark)).theme.colors.frame, [29, 32, 33]);
});

// Chromium ignores a new-tab override inside a theme, so the page is its own extension; its key fixes the id whatever folder it loads from.
test('the new-tab extension overrides the new tab with a fixed id and reads the top sites and the search engine', () => {
  const m = JSON.parse(renderNewtabManifest());
  assert.equal(m.manifest_version, 3);
  assert.deepEqual(m.chrome_url_overrides, { newtab: 'newtab.html' });
  assert.deepEqual(m.permissions, ['topSites', 'search', 'tabs']);
  assert.deepEqual(m.background, { service_worker: 'bg.js' });
  assert.equal(m.theme, undefined);
  const der = Buffer.from(m.key, 'base64');
  const id = createHash('sha256').update(der).digest('hex').slice(0, 32).replace(/[0-9a-f]/g, (c) => 'abcdefghijklmnop'[parseInt(c, 16)]);
  assert.equal(id, 'aakconifmcmaooplokgfeaepglecbmaf');
});

test('the new-tab page names its scheme and loads its colours, its look and its script', () => {
  for (const t of [light, dark, artboard]) {
    const html = renderNewtabHtml(t);
    assert.match(html, new RegExp(`<html lang="en" data-theme="${t.name}">`), t.name);
    assert.match(html, /<title>New Tab<\/title>/);
    assert.match(html, /<link rel="stylesheet" href="theme.css">\s*<link rel="stylesheet" href="newtab.css">/);
    assert.match(html, /<script type="module" src="newtab.js"><\/script>/);
    assert.match(html, /<input id="q" type="text"[^>]*aria-label="Search"/);
  }
});

test('the new-tab page draws in the scheme\'s paper, ink and fonts, on the dot grid', () => {
  const vars = (t) => Object.fromEntries([...renderNewtabCss(t).matchAll(/--([a-z-]+): ([^;]+);/g)].map((m) => [m[1], m[2]]));
  assert.deepEqual(
    { paper: vars(artboard).paper, ink: vars(artboard).ink, surface: vars(artboard).surface, accent: vars(artboard).accent, display: vars(artboard).display, ui: vars(artboard).ui },
    { paper: '#E4E6EA', ink: '#15171B', surface: '#FFFFFF', accent: '#3D5AFE', display: '"Maple Mono"', ui: '"Maple Mono"' },
  );
  assert.equal(vars(dark).paper, '#1D2021');
  assert.match(renderNewtabCss(artboard), /radial-gradient\(#D0D7DE 1px, transparent 1.3px\)/);
  assert.match(renderNewtabCss(artboard), /background-size: 16px 16px;/);
  assert.match(renderNewtabCss(dark), /radial-gradient\(#3C3836 1px, transparent 1.3px\)/);
  assert.match(renderNewtabCss(light), /color-scheme: light;/);
  assert.match(renderNewtabCss(dark), /color-scheme: dark;/);
});

test('colors.fish sets fish and fzf colours', () => {
  const fish = renderFish(dark);
  assert.match(fish, /^set -g fish_color_normal ebdbb2$/m);
  // The prompt draws the directory and a failed status in these.
  assert.match(fish, /^set -g fish_color_cwd 83a598$/m);
  assert.match(fish, /^set -g fish_color_status ff4f39$/m);
  assert.match(fish, /^set -gx FZF_DEFAULT_OPTS "--color=fg:#ebdbb2,bg:#282828,hl:#83a598/m);
});

test('yazi theme sets the keys yazi 26.9 reads', () => {
  const y = renderYazi(dark);
  assert.match(y, /^\[mgr\]$/m);
  assert.match(y, /^cwd = \{ fg = "lightblue" \}$/m);
  assert.match(y, /^hovered = \{ fg = "#282828", bg = "lightblue" \}$/m);
  assert.match(y, /^\[mode\]$/m);
  assert.match(y, /^\[status\]$/m);
  assert.match(y, /^border_style = \{ fg = "#433f3b" \}$/m);
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
  writeFileSync(join(out, 'colors.fish'), renderFish(light));
  const config = new URL('../../home/dot_config/fish/config.fish', import.meta.url).pathname;
  // One fish: the config at start, then a new colours file and a prompt, as after dots colorscheme.
  const script = `source ${config}; echo $fish_color_normal; echo '${renderFish(dark).replace(/'/g, "\\'")}' > ${out}/colors.fish; emit fish_prompt; echo $fish_color_normal`;
  const seen = execFileSync('fish', ['--no-config', '-c', script], { env: { ...process.env, XDG_STATE_HOME: state }, encoding: 'utf8' }).trim().split('\n');
  assert.deepEqual(seen, [light.color.ink.slice(1).toLowerCase(), 'ebdbb2']);
});

// claude, pi and amx kept v1's dark palette, so on a light scheme they drew dark boxes in a light terminal.
test('the Claude Code theme starts from the light or dark preset of the scheme and takes its tokens', () => {
  const a = JSON.parse(renderClaude(artboard));
  assert.equal(a.name, 'dots');
  assert.equal(a.base, 'light');
  assert.deepEqual([a.overrides.claude, a.overrides.text, a.overrides.inverseText, a.overrides.success, a.overrides.error], ['#3d5afe', '#15171b', '#ffffff', '#1a7f37', '#cf222e']);
  assert.equal(a.overrides.diffAdded, '#ddece1');
  const b = JSON.parse(renderClaude(dark));
  assert.equal(b.base, 'dark');
  assert.equal(b.overrides.claude, '#83a598');
});

// Claude Code 2.1.303's theme keys; a key left out falls back to Claude's own preset colour.
const CLAUDE_KEYS = [
  'autoAccept', 'autoAcceptShimmer', 'skill', 'bashBorder', 'claude', 'claudeShimmer', 'claudeBlue_FOR_SYSTEM_SPINNER', 'claudeBlueShimmer_FOR_SYSTEM_SPINNER',
  'permission', 'permissionShimmer', 'planMode', 'ide', 'promptBorder', 'promptBorderShimmer', 'text', 'inverseText', 'inactive', 'inactiveShimmer',
  'subtle', 'suggestion', 'remember', 'background', 'success', 'error', 'warning', 'merged', 'warningShimmer', 'diffAdded', 'diffRemoved',
  'diffAddedDimmed', 'diffRemovedDimmed', 'diffAddedWord', 'diffRemovedWord', 'red_FOR_SUBAGENTS_ONLY', 'blue_FOR_SUBAGENTS_ONLY',
  'green_FOR_SUBAGENTS_ONLY', 'yellow_FOR_SUBAGENTS_ONLY', 'purple_FOR_SUBAGENTS_ONLY', 'orange_FOR_SUBAGENTS_ONLY', 'pink_FOR_SUBAGENTS_ONLY',
  'cyan_FOR_SUBAGENTS_ONLY', 'professionalBlue', 'chromeYellow', 'clawd_body', 'clawd_background', 'userMessageBackground',
  'userMessageBackgroundHover', 'composerSidebarBackground', 'selectionBg', 'bashMessageBackgroundColor', 'memoryBackgroundColor',
  'rate_limit_fill', 'rate_limit_empty', 'fastMode', 'fastModeShimmer', 'effortUltra', 'briefLabelYou', 'briefLabelClaude', 'rainbow_red',
  'rainbow_orange', 'rainbow_yellow', 'rainbow_green', 'rainbow_blue', 'rainbow_indigo', 'rainbow_violet', 'rainbow_red_shimmer',
  'rainbow_orange_shimmer', 'rainbow_yellow_shimmer', 'rainbow_green_shimmer', 'rainbow_blue_shimmer', 'rainbow_indigo_shimmer',
  'rainbow_violet_shimmer',
];

test('the Claude Code theme sets every colour Claude reads, subagents and the sidebar included', () => {
  const o = JSON.parse(renderClaude(light)).overrides;
  assert.deepEqual(Object.keys(o).sort(), [...CLAUDE_KEYS].sort());
  for (const [k, v] of Object.entries(o)) assert.match(v, /^#[0-9a-f]{6}$/, k);
  assert.equal(o.red_FOR_SUBAGENTS_ONLY, '#cf222e');
  assert.equal(o.cyan_FOR_SUBAGENTS_ONLY, '#1b7c83');
  assert.equal(o.composerSidebarBackground, '#f2f2f2');
});

test('pi colours code from the scheme syntax table, as kak and helix do', () => {
  const p = JSON.parse(renderPi(light));
  const hex = (role) => p.vars[p.colors[role]];
  assert.deepEqual(['syntaxKeyword', 'syntaxFunction', 'syntaxString', 'syntaxNumber', 'syntaxType', 'syntaxComment'].map(hex),
    ['#cf222e', '#8250df', '#0a3069', '#0550ae', '#953800', '#59636e']);
});

test('pi dim text reads at 4.5:1 on every scheme and stays dimmer than its muted text', () => {
  for (const name of schemeNames()) {
    const v = JSON.parse(renderPi(loadScheme(name))).vars;
    assert.ok(contrast(v.dimText, v.background) >= 4.5, `${name}: ${contrast(v.dimText, v.background)}`);
    assert.ok(contrast(v.dimText, v.background) < contrast(v.mutedText, v.background), name);
  }
});

test('pi sets its optional colours and export page, and points at the pi.dev schema', () => {
  const p = JSON.parse(renderPi(light));
  for (const k of ['scrollbarTrack', 'scrollbarThumb', 'searchMatchBg', 'searchMatchText', 'thinkingMax']) assert.ok(p.colors[k] in p.vars, k);
  for (const k of ['pageBg', 'cardBg', 'infoBg']) assert.ok(p.export[k] in p.vars, k);
  assert.equal(p.$schema, 'https://pi.dev/schemas/theme.schema.json');
});

test('the pi theme names its appearance, sits on the terminal surface, and every colour resolves to a var', () => {
  const a = JSON.parse(renderPi(artboard));
  assert.deepEqual([a.name, a.appearance, a.vars.background, a.vars.foreground, a.vars.accent], ['dots', 'light', '#ffffff', '#15171b', '#3d5afe']);
  assert.equal(JSON.parse(renderPi(dark)).appearance, 'dark');
  assert.ok(Object.keys(a.colors).length >= 51, `${Object.keys(a.colors).length} colours`);
  for (const [k, v] of Object.entries(a.colors)) assert.ok(v in a.vars, `${k}: ${v}`);
});

test('the amx theme sets its six roles from the tokens', () => {
  assert.equal(
    renderAmx(artboard),
    ['waiting = "#9a6700"', 'done = "#1a7f37"', 'failed = "#cf222e"', 'stopped = "#57606a"', 'accent = "#3d5afe"', 'cursor = "#d0d7de"', ''].join('\n'),
  );
});

test('helix takes the kak look: syntax colours, a flat status line, and the menu and popups on a 6% ink tint', () => {
  const hx = renderHelix(light);
  assert.match(hx, /^"ui\.background" = \{ bg = "#ffffff" \}$/m);
  assert.match(hx, /^"keyword" = \{ fg = "#cf222e", modifiers = \["bold"\] \}$/m);
  assert.match(hx, /^"comment" = \{ fg = "#59636e", modifiers = \["italic"\] \}$/m);
  assert.match(hx, /^"string" = "#0a3069"$/m);
  assert.match(hx, /^"ui\.statusline" = \{ fg = "#1f2328", bg = "#ffffff" \}$/m);
  assert.match(hx, /^"ui\.statusline\.normal" = \{ fg = "#0969da", bg = "#ffffff", modifiers = \["bold"\] \}$/m);
  assert.match(hx, /^"ui\.popup" = \{ fg = "#1f2328", bg = "#f2f2f2" \}$/m);
  assert.match(hx, /^"ui\.menu\.selected" = \{ fg = "#ffffff", bg = "#0969da" \}$/m);
  assert.match(hx, /^"diagnostic\.error" = \{ underline = \{ color = "#d1242f", style = "curl" \} \}$/m);
  assert.match(renderHelix(dark), /^"function" = "#b8bb26"$/m);
});

// mpv reads # as a comment, so every colour is quoted; the OSC takes its colours through script-opts.
test('the mpv fragment sets the OSD, the subtitle font and the OSC colours from the tokens', () => {
  const conf = renderMpv(dark);
  assert.match(conf, /^osd-color="#ebdbb2"$/m);
  assert.match(conf, /^osd-back-color="#282828"$/m);
  assert.match(conf, /^osd-border-color="#282828"$/m);
  assert.match(conf, /^osd-font="Maple Mono"$/m);
  assert.match(conf, /^script-opts-append="osc-background_color=#282828"$/m);
  assert.match(conf, /^script-opts-append="osc-held_element_color=#83a598"$/m);
  assert.match(renderMpv(light), /^sub-font="Maple Mono"$/m);
  for (const line of conf.trim().split('\n')) assert.match(line, /^[a-z-]+="[^"]+"$/);
});

// Dark themes recolour the page, keeping image hues, as v1 did; a light theme sets recolor false outright, since a re-source keeps any option it does not name.
test('the zathura fragment sets every colour, the font, and recolours pages only in dark themes', () => {
  const z = renderZathura(dark);
  assert.match(z, /^set default-bg "#1d2021"$/m);
  assert.match(z, /^set statusbar-fg "#ebdbb2"$/m);
  assert.match(z, /^set index-active-bg "#83a598"$/m);
  assert.match(z, /^set font "Maple Mono 11"$/m);
  assert.match(z, /^set recolor true$/m);
  assert.match(z, /^set recolor-keephue true$/m);
  assert.match(z, /^set recolor-lightcolor "#1d2021"$/m);
  assert.match(z, /^set recolor-darkcolor "#ebdbb2"$/m);
  for (const t of [light, artboard]) {
    assert.match(renderZathura(t), /^set recolor false$/m, t.name);
    assert.match(renderZathura(t), new RegExp(`^set default-bg "${t.color.paper.toLowerCase()}"$`, 'm'), t.name);
  }
  for (const k of ['default', 'statusbar', 'inputbar', 'index', 'index-active', 'completion', 'completion-group', 'completion-highlight', 'notification', 'notification-error', 'notification-warning']) {
    assert.match(z, new RegExp(`^set ${k}-bg "#[0-9a-f]{6}"$`, 'm'), k);
    assert.match(z, new RegExp(`^set ${k}-fg "#[0-9a-f]{6}"$`, 'm'), k);
  }
});

// imv has no include, so the theme renders its whole config, v1's binds with it.
test('the imv config sits the image on light with the overlay in ink on surface, and keeps v1\'s trash binds', () => {
  const imv = renderImv(dark);
  assert.match(imv, /^\[options\]$/m);
  assert.match(imv, /^background = 1d2021$/m);
  assert.match(imv, /^overlay_text_color = ebdbb2$/m);
  assert.match(imv, /^overlay_background_color = 282828$/m);
  assert.match(imv, /^overlay_font = Maple Mono:14$/m);
  assert.match(imv, /^\[binds\]\n<Ctrl\+x> = exec gio trash -- "\$imv_current_file"; quit\n<Ctrl\+Shift\+X> = exec gio trash -- "\$imv_current_file"; close$/m);
  assert.match(renderImv(light), /^background = e8eaed$/m);
});

// wl-kbptr's labels and boxes in the theme's colours and face: ink labels, the typed part in accent, the screen washed in light.
test('the wl-kbptr config draws its labels in ink and the theme\'s face, picks in accent and washes the screen in paper', () => {
  const k = renderKbptr(dark);
  for (const mode of ['tile', 'floating', 'bisect']) {
    const section = k.split(/^(?=\[)/m).find((s) => s.startsWith(`[mode_${mode}]`));
    assert.ok(section, mode);
    assert.match(section, /^label_color=#ebdbb2ff$/m);
    assert.match(section, /^label_font_family=Maple Mono$/m);
    assert.match(section, /^unselectable_bg_color=#1d202199$/m);
  }
  assert.match(k, /^\[mode_floating\]\n(?:.*\n)*?selectable_border_color=#83a598ff$/m);
  assert.match(k, /^label_select_color=#83a598ff$/m);
  assert.match(k, /^pointer_color=#83a598ff$/m);
  assert.doesNotMatch(k, /^\[general\]/m);
  assert.match(renderKbptr(light), /^unselectable_bg_color=#e8eaed99$/m);
});

// Every pair of text and ground an app theme draws reads at 4.5:1 in every scheme.
const kakFace = (out, name) => {
  const m = out.match(new RegExp(`^face global ${name} rgb:([0-9a-f]{6})(?:,rgb:([0-9a-f]{6}))?`, 'm'));
  return [m[1], m[2]].map((x) => (x ? '#' + x : undefined));
};
const tmuxPair = (t, name) => {
  const m = tmuxOpt(t, name).match(/fg=(#[0-9a-f]{6}),bg=(#[0-9a-f]{6})/);
  return [m[1], m[2]];
};
const zathuraPair = (out, k) => [`${k}-fg`, `${k}-bg`].map((o) => out.match(new RegExp(`^set ${o} "(#[0-9a-f]{6})"$`, 'm'))[1]);
const yaziPair = (out, k) => { const m = out.match(new RegExp(`^${k} = \\{ fg = "(#[0-9a-f]{6})", bg = "(#[0-9a-f]{6})"`, 'm')); return m ? [m[1], m[2]] : null; };

test('every text and ground pair the app themes draw reads at 4.5:1 in every scheme', () => {
  const bad = [];
  const need = (name, what, fg, bg, min = 4.5) => { const r = contrast(fg, bg); if (r < min) bad.push(`${name} ${what} ${r.toFixed(2)}`); };
  for (const name of schemeNames()) {
    const t = loadScheme(name);
    for (const k of ['menu-style', 'menu-selected-style', 'message-style', 'message-command-style', 'mode-style', 'copy-mode-match-style', 'copy-mode-current-match-style']) need(name, `tmux ${k}`, ...tmuxPair(t, k));
    const kak = renderKak(t);
    const menuBg = kakFace(kak, 'MenuBackground')[1];
    need(name, 'kak MenuInfo', kakFace(kak, 'MenuInfo')[0], menuBg);
    need(name, 'kak MenuBackground', ...kakFace(kak, 'MenuBackground'));
    for (const k of ['PrimarySelection', 'MenuForeground', 'Error', 'StatusCursor', 'MatchingChar', 'LineNumbers', 'StatusLineInfo']) need(name, `kak ${k}`, ...kakFace(kak, k));
    const z = renderZathura(t);
    for (const k of ['statusbar', 'inputbar', 'index', 'index-active', 'completion', 'completion-group', 'completion-highlight', 'notification', 'notification-error', 'notification-warning']) need(name, `zathura ${k}`, ...zathuraPair(z, k));
    const y = renderYazi(t);
    for (const k of ['hovered', 'tab_active', 'tab_inactive', 'normal_main', 'normal_alt', 'select_main', 'unset_main']) {
      const p = yaziPair(y, k);
      if (p) need(name, `yazi ${k}`, ...p);
    }
    const o = JSON.parse(renderClaude(t)).overrides;
    const bg = t.color.surface.toLowerCase();
    need(name, 'claude inactive', o.inactive, bg);
    for (const k of ['diffAdded', 'diffRemoved', 'diffAddedWord', 'diffRemovedWord', 'userMessageBackground', 'selectionBg']) need(name, `claude text on ${k}`, o.text, o[k]);
    const v = JSON.parse(renderPi(t)).vars;
    for (const k of ['selectedBackground', 'panel', 'panelPending', 'panelSuccess', 'panelError', 'highlight']) need(name, `pi text on ${k}`, v.foreground, v[k]);
  }
  assert.deepEqual(bad, []);
});

test("the coding agents' borders, helix's split and yazi's frame are the quiet frame in every scheme", () => {
  for (const name of schemeNames()) {
    const t = loadScheme(name);
    const frame = t.niri.border_inactive.toLowerCase();
    const o = JSON.parse(renderClaude(t)).overrides;
    assert.equal(o.promptBorder, frame, `${name} claude`);
    const v = JSON.parse(renderPi(t)).vars;
    assert.deepEqual([v.border, v.borderMuted], [frame, frame], `${name} pi`);
    assert.equal(JSON.parse(renderPi(t)).colors.borderAccent, 'border', `${name} pi accent border`);
    assert.match(renderHelix(t), new RegExp(`^"ui.window" = "${frame}"$`, 'm'), `${name} helix`);
    assert.match(renderYazi(t), new RegExp(`^border_style = \\{ fg = "${frame}" \\}$`, 'm'), `${name} yazi`);
  }
});

test("a terminal's theme takes the paper as its ground and leaves the theme itself alone", () => {
  const t = loadScheme('gruvbox-dark');
  assert.equal(termTheme(t).color.surface, t.color.paper);
  assert.equal(t.color.surface, '#282828');
});

test('a word that already reads on the paper and the field stays its own colour', () => {
  assert.equal(termTheme(loadScheme('gruvbox-dark')).color.ink, '#EBDBB2');
  assert.equal(termTheme(loadScheme('catppuccin-mocha')).syntax.keyword, '#CBA6F7');
});

// A terminal is clear, so its words sit on the paper or anywhere on the field; each must read on all three.
test("every scheme's terminal words read on its paper and on both ends of its field: text at 4.5:1, a comment and the ANSI hues at 3:1", () => {
  for (const n of schemeNames()) {
    const t = loadScheme(n);
    const term = termTheme(t);
    const c = term.color;
    for (const ground of [t.color.paper, t.paper.grade.from, t.paper.grade.to]) {
      const floor = (what, hex, min) => assert.ok(contrast(hex, ground) >= min, `${n} ${what} ${hex} on ${ground}: ${contrast(hex, ground).toFixed(2)}`);
      for (const k of ['ink', 'muted', 'accent', 'danger', 'ok']) floor(k, c[k], 4.5);
      for (const [k, v] of Object.entries(term.syntax)) floor(`syntax.${k}`, v, k === 'comment' ? 3 : 4.5);
      c.ansi.forEach((v, i) => { if (![0, 7, 15].includes(i)) floor(`ansi ${i}`, v, 3); });
    }
  }
});

test("one-light's grey paper darkens its terminal accent until it reads", () => {
  assert.equal(termTheme(loadScheme('one-light')).color.accent, '#214490');
});

const BTOP_KEYS = ['main_bg', 'main_fg', 'title', 'hi_fg', 'selected_bg', 'selected_fg', 'inactive_fg', 'graph_text', 'meter_bg', 'proc_misc', 'cpu_box', 'mem_box', 'net_box', 'proc_box', 'div_line',
  ...['temp', 'cpu', 'free', 'cached', 'available', 'used', 'download', 'upload', 'process'].flatMap((g) => [`${g}_start`, `${g}_mid`, `${g}_end`])];
const btopTheme = (t) => Object.fromEntries([...renderBtop(t).matchAll(/^theme\[([a-z_]+)\]="([^"]*)"$/gm)].map((m) => [m[1], m[2]]));

test('btop sits clear on the desk, its boxes in the quiet frame, its keys and selection in the accent, every key set', () => {
  const t = termTheme(loadScheme('artboard'));
  const b = btopTheme(t);
  assert.deepEqual(Object.keys(b).sort(), [...BTOP_KEYS].sort());
  assert.equal(b.main_bg, '', 'empty is the terminal\'s own, clear, background');
  assert.equal(b.main_fg, t.color.ink.toLowerCase());
  assert.equal(b.hi_fg, t.color.accent.toLowerCase());
  for (const k of ['cpu_box', 'mem_box', 'net_box', 'proc_box', 'div_line']) assert.equal(b[k], t.niri.border_inactive.toLowerCase(), k);
  assert.ok(contrast(b.selected_fg.toUpperCase(), b.selected_bg.toUpperCase()) >= 4.5, 'the selected row reads');
});

test("lazygit's theme borders the focused view in the accent and lights its line on a tint the ink reads on", () => {
  const t = termTheme(loadScheme('gruvbox-material-dark'));
  const y = renderLazygit(t);
  assert.match(y, /^gui:\n  theme:\n/);
  const get = (k) => y.match(new RegExp(`^    ${k}: \\[(.*)\\]$`, 'm'))?.[1];
  assert.equal(get('activeBorderColor'), `'${t.color.accent.toLowerCase()}', 'bold'`);
  assert.equal(get('inactiveBorderColor'), `'${t.niri.border_inactive.toLowerCase()}'`);
  assert.equal(get('unstagedChangesColor'), `'${t.color.danger.toLowerCase()}'`);
  assert.equal(get('defaultFgColor'), "'default'");
  const bg = get('selectedLineBgColor').slice(1, -1);
  assert.ok(contrast(t.color.ink, bg.toUpperCase()) >= 4.5, `ink on ${bg}`);
  for (const k of ['searchingActiveBorderColor', 'optionsTextColor', 'inactiveViewSelectedLineBgColor', 'cherryPickedCommitFgColor', 'cherryPickedCommitBgColor', 'markedBaseCommitFgColor', 'markedBaseCommitBgColor']) assert.ok(get(k), k);
});

const cssVars = (css) => Object.fromEntries([...css.matchAll(/^  --([a-z-]+): (#[0-9a-f]{6,8});$/gm)].map((m) => [m[1], m[2]]));

test("GTK 4's window, views, header bar and sidebar are clear on the desk, its popovers and dialogs solid paper, in libadwaita's variables", () => {
  const t = termTheme(loadScheme('artboard'));
  const css = renderGtk4Css(t);
  const v = cssVars(css);
  const paper = t.color.paper.toLowerCase();
  for (const k of ['window-bg-color', 'view-bg-color', 'headerbar-bg-color', 'sidebar-bg-color']) assert.equal(v[k], `${paper}00`, k);
  for (const k of ['popover-bg-color', 'dialog-bg-color']) assert.equal(v[k], paper, k);
  for (const k of ['window-fg-color', 'view-fg-color', 'headerbar-fg-color', 'popover-fg-color']) assert.equal(v[k], t.color.ink.toLowerCase(), k);
  assert.deepEqual([v['accent-bg-color'], v['accent-color'], v['destructive-bg-color']], [t.color.accent, t.color.accent, t.color.danger].map((x) => x.toLowerCase()));
  assert.ok(contrast(t.color.paper, t.color.accent) >= 4.5, 'a suggested button\'s words read on the accent');
});

test('plain GTK 4, whose own theme reads no variable, is cleared and coloured through selectors that use them', () => {
  const css = renderGtk4Css(termTheme(loadScheme('gruvbox-material-dark')));
  assert.match(css, /window\.background, headerbar,[^{]*\.view,[^{]*\{\n  background-color: transparent;/);
  assert.match(css, /popover > contents,[^{]*\{\n  background-color: var\(--popover-bg-color\);/);
  assert.match(css, /button\.suggested-action \{ background-color: var\(--accent-bg-color\); color: var\(--accent-fg-color\); \}/);
});
