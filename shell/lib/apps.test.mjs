import { test } from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { readFileSync, readdirSync, mkdtempSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createHash } from 'node:crypto';
import { parseToml } from './toml.mjs';
import { validateTheme, contrast } from './theme.mjs';
import { renderTmux, renderKak, renderHelix, renderYazi, renderFish, renderGtkCss, renderGtkSettings, renderChromiumTheme, renderNewtabManifest, renderNewtabHtml, renderNewtabCss, renderClaude, renderPi, renderAmx, renderMpv, renderZathura, renderImv, renderKbptr } from './apps.mjs';

const load = (name) => validateTheme(parseToml(readFileSync(new URL(`../../themes/${name}/theme.toml`, import.meta.url), 'utf8')));
const blueprint = load('blueprint');
const paper = load('paper');

const artboard = load('artboard');

// The tmux bar reads as the page's running head, in the margins' voice: Paper's caps and dashes, Artboard's accent dot, Blueprint's brackets.
const tmuxOpt = (t, name) => renderTmux(t).match(new RegExp(`^set -g ${name} "(.*)"$`, 'm'))[1];

test('the tmux bar draws no filled block in any theme, only text in the margin colours', () => {
  for (const t of [paper, artboard, blueprint]) {
    for (const o of ['status-left', 'status-right', 'window-status-format', 'window-status-current-format']) {
      assert.doesNotMatch(tmuxOpt(t, o), /bg=(?!default)/, `${t.name} ${o}`);
    }
  }
});

test('tmux windows read like the margin number: Paper 01 FISH in ink, Blueprint [01] in cyan, Artboard an accent dot', () => {
  const caps = /s\/a\/A\//;
  assert.match(tmuxOpt(paper, 'window-status-current-format'), /^#\[fg=#1c1915,bold\]#\{\?#\{e\|<:#\{window_index\},10\},0,\}#\{window_index\}#\[nobold\] /);
  assert.match(tmuxOpt(paper, 'window-status-current-format'), caps);
  assert.match(tmuxOpt(paper, 'window-status-format'), /^#\[fg=#575653\]/);
  assert.match(tmuxOpt(blueprint, 'window-status-current-format'), /^#\[fg=#7fe3f0\]\[#\{\?/);
  assert.match(tmuxOpt(artboard, 'window-status-current-format'), /^#\[fg=#3d5afe\]● #\[fg=#15171b,bold\]/);
  assert.doesNotMatch(tmuxOpt(artboard, 'window-status-current-format'), caps);
  assert.equal(tmuxOpt(paper, 'window-status-separator'), '#[fg=#575653] — ');
  assert.equal(tmuxOpt(blueprint, 'window-status-separator'), '#[fg=#80a4c2] · ');
});

test('the tmux session drops amx\'s prefix, turns the accent while the prefix key is held, and agents speak in the margin voice', () => {
  assert.match(tmuxOpt(paper, 'status-left'), /^ #\[fg=#\{\?client_prefix,#c8381e,#575653\}\]#\{s\/\^amx-\/\/;=\/24\/…;s\/a\/A\//);
  assert.match(tmuxOpt(paper, 'status-right'), /^#\(dots-agents caps 575653 c8381e 1c1915\)/);
  assert.match(tmuxOpt(artboard, 'status-right'), /^#\(dots-agents plain 57606a 3d5afe 15171b\)/);
  assert.match(tmuxOpt(blueprint, 'status-right'), /^#\(dots-agents bracket 80a4c2 ffb547 d6f4f8\)/);
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
  execFileSync('tmux', ['-L', sock, '-f', '/dev/null', 'new-session', '-d', '-s', 'amx-dots']);
  for (const theme of [paper, artboard, blueprint]) {
    writeFileSync(join(dir, 'tmux.conf'), renderTmux(theme));
    tmux('source-file', join(dir, 'tmux.conf'));
    assert.match(tmux('show', '-g', 'status-style'), new RegExp(`fg=${theme.color.muted.toLowerCase()},bg=default`));
    // Without the prefix held, the session reads in the muted colour, without amx's prefix and in the theme's case.
    const name = theme.type.voice === 'plain' ? 'dots' : 'DOTS';
    assert.equal(tmux('display', '-p', '#{T:status-left}'), ` #[fg=${theme.color.muted.toLowerCase()}]${name}#[default] \n`);
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

// A colour policy would block the theme extension, so the manifest alone carries the exact colours, from Chromium's next start.
test('the chromium theme extension frames the window in paper and draws the toolbar on surface', () => {
  const rgbOf = (hex) => [1, 3, 5].map((i) => parseInt(hex.slice(i, i + 2), 16));
  for (const t of [paper, blueprint, artboard]) {
    const m = JSON.parse(renderChromiumTheme(t));
    assert.equal(m.manifest_version, 3);
    assert.deepEqual(m.theme.colors.frame, rgbOf(t.color.paper), t.name);
    assert.deepEqual(m.theme.colors.toolbar, rgbOf(t.color.surface), t.name);
    assert.deepEqual(m.theme.colors.toolbar_text, rgbOf(t.color.ink), t.name);
    assert.deepEqual(m.theme.colors.ntp_background, rgbOf(t.color.paper), t.name);
  }
  assert.deepEqual(JSON.parse(renderChromiumTheme(blueprint)).theme.colors.frame, [12, 26, 46]);
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

test('the new-tab page names its theme\'s voice and loads its theme, its look and its script', () => {
  for (const [t, voice] of [[paper, 'caps'], [blueprint, 'bracket'], [artboard, 'plain']]) {
    const html = renderNewtabHtml(t);
    assert.match(html, new RegExp(`<html lang="en" data-voice="${voice}" data-theme="${t.name}">`), t.name);
    assert.match(html, /<title>New Tab<\/title>/);
    assert.match(html, /<link rel="stylesheet" href="theme.css">\s*<link rel="stylesheet" href="newtab.css">/);
    assert.match(html, /<script type="module" src="newtab.js"><\/script>/);
    assert.match(html, /<input id="q" type="text"[^>]*aria-label="Search"/);
  }
});

test('the new-tab page draws in the theme\'s paper, ink and fonts, on its paper\'s texture', () => {
  const vars = (t) => Object.fromEntries([...renderNewtabCss(t).matchAll(/--([a-z-]+): ([^;]+);/g)].map((m) => [m[1], m[2]]));
  assert.deepEqual(
    { paper: vars(paper).paper, ink: vars(paper).ink, surface: vars(paper).surface, accent: vars(paper).accent, display: vars(paper).display, ui: vars(paper).ui },
    { paper: '#F1E9D8', ink: '#1C1915', surface: '#FAF6EC', accent: '#C8381E', display: '"Instrument Serif"', ui: '"Maple Mono"' },
  );
  assert.equal(vars(blueprint).paper, '#0C1A2E');
  assert.equal(vars(blueprint).display, '"Maple Mono"');
  assert.equal(vars(artboard).paper, '#E4E6EA');
  assert.match(renderNewtabCss(blueprint), /linear-gradient\(rgba\(127, 227, 240, 0.13\) 1px, transparent 1px\)/);
  assert.match(renderNewtabCss(blueprint), /background-size: 80px 80px, 80px 80px, 16px 16px, 16px 16px;/);
  assert.match(renderNewtabCss(artboard), /radial-gradient\(#B4BAC4 1px, transparent 1.3px\)/);
  assert.match(renderNewtabCss(artboard), /background-size: 16px 16px;/);
  assert.match(renderNewtabCss(paper), /feTurbulence/);
  // As the shell's grain shader does, the noise scales the paper by 1 +- grain, so its mean stays the paper colour.
  assert.match(renderNewtabCss(paper), /flood-color='%23F1E9D8'/);
  assert.match(renderNewtabCss(paper), /operator='arithmetic' k1='0.12' k2='0.94' k3='0' k4='0'/);
  assert.match(renderNewtabCss(paper), /color-scheme: light;/);
  assert.match(renderNewtabCss(blueprint), /color-scheme: dark;/);
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

// claude, pi and amx kept v1's dark palette, so on Paper and Artboard they drew dark boxes in a light terminal.
test('the Claude Code theme starts from the light or dark preset of the theme and takes its tokens', () => {
  const a = JSON.parse(renderClaude(artboard));
  assert.equal(a.name, 'dots');
  assert.equal(a.base, 'light');
  assert.deepEqual([a.overrides.claude, a.overrides.text, a.overrides.inverseText, a.overrides.success, a.overrides.error], ['#3d5afe', '#15171b', '#ffffff', '#1a7f37', '#cf222e']);
  assert.equal(a.overrides.diffAdded, '#ddece1');
  const b = JSON.parse(renderClaude(blueprint));
  assert.equal(b.base, 'dark');
  assert.equal(b.overrides.claude, '#7fe3f0');
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
  const o = JSON.parse(renderClaude(paper)).overrides;
  assert.deepEqual(Object.keys(o).sort(), [...CLAUDE_KEYS].sort());
  for (const [k, v] of Object.entries(o)) assert.match(v, /^#[0-9a-f]{6}$/, k);
  assert.equal(o.red_FOR_SUBAGENTS_ONLY, '#c8381e');
  assert.equal(o.cyan_FOR_SUBAGENTS_ONLY, '#24837b');
  assert.equal(o.composerSidebarBackground, '#ede9df');
});

test('pi colours code from the theme syntax table, as kak and helix do', () => {
  const p = JSON.parse(renderPi(paper));
  const hex = (role) => p.vars[p.colors[role]];
  assert.deepEqual(['syntaxKeyword', 'syntaxFunction', 'syntaxString', 'syntaxNumber', 'syntaxType', 'syntaxComment'].map(hex),
    ['#66800b', '#bc5215', '#24837b', '#bc5215', '#8e6b01', '#575653']);
});

test('pi dim text reads at 4.5:1 on every theme and stays dimmer than its muted text', () => {
  for (const t of [paper, artboard, blueprint]) {
    const v = JSON.parse(renderPi(t)).vars;
    assert.ok(contrast(v.dimText, v.background) >= 4.5, `${t.name}: ${contrast(v.dimText, v.background)}`);
    assert.ok(contrast(v.dimText, v.background) < contrast(v.mutedText, v.background), t.name);
  }
});

test('pi sets its optional colours and export page, and points at the pi.dev schema', () => {
  const p = JSON.parse(renderPi(paper));
  for (const k of ['scrollbarTrack', 'scrollbarThumb', 'searchMatchBg', 'searchMatchText', 'thinkingMax']) assert.ok(p.colors[k] in p.vars, k);
  for (const k of ['pageBg', 'cardBg', 'infoBg']) assert.ok(p.export[k] in p.vars, k);
  assert.equal(p.$schema, 'https://pi.dev/schemas/theme.schema.json');
});

test('the pi theme names its appearance, sits on the terminal surface, and every colour resolves to a var', () => {
  const a = JSON.parse(renderPi(artboard));
  assert.deepEqual([a.name, a.appearance, a.vars.background, a.vars.foreground, a.vars.accent], ['dots', 'light', '#ffffff', '#15171b', '#3d5afe']);
  assert.equal(JSON.parse(renderPi(blueprint)).appearance, 'dark');
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

// mpv reads # as a comment, so every colour is quoted; the OSC takes its colours through script-opts.
test('the mpv fragment sets the OSD, the subtitle font and the OSC colours from the tokens', () => {
  const conf = renderMpv(blueprint);
  assert.match(conf, /^osd-color="#d6f4f8"$/m);
  assert.match(conf, /^osd-back-color="#0a1526"$/m);
  assert.match(conf, /^osd-border-color="#0a1526"$/m);
  assert.match(conf, /^osd-font="Maple Mono"$/m);
  assert.match(conf, /^script-opts-append="osc-background_color=#0a1526"$/m);
  assert.match(conf, /^script-opts-append="osc-held_element_color=#7fe3f0"$/m);
  assert.match(renderMpv(paper), /^sub-font="Instrument Serif"$/m);
  for (const line of conf.trim().split('\n')) assert.match(line, /^[a-z-]+="[^"]+"$/);
});

// Dark themes recolour the page, keeping image hues, as v1 did; a light theme sets recolor false outright, since a re-source keeps any option it does not name.
test('the zathura fragment sets every colour, the font, and recolours pages only in dark themes', () => {
  const z = renderZathura(blueprint);
  assert.match(z, /^set default-bg "#0c1a2e"$/m);
  assert.match(z, /^set statusbar-fg "#d6f4f8"$/m);
  assert.match(z, /^set index-active-bg "#7fe3f0"$/m);
  assert.match(z, /^set font "Maple Mono 11"$/m);
  assert.match(z, /^set recolor true$/m);
  assert.match(z, /^set recolor-keephue true$/m);
  assert.match(z, /^set recolor-lightcolor "#0c1a2e"$/m);
  assert.match(z, /^set recolor-darkcolor "#d6f4f8"$/m);
  for (const t of [paper, artboard]) {
    assert.match(renderZathura(t), /^set recolor false$/m, t.name);
    assert.match(renderZathura(t), new RegExp(`^set default-bg "${t.color.paper.toLowerCase()}"$`, 'm'), t.name);
  }
  for (const k of ['default', 'statusbar', 'inputbar', 'index', 'index-active', 'completion', 'completion-group', 'completion-highlight', 'notification', 'notification-error', 'notification-warning']) {
    assert.match(z, new RegExp(`^set ${k}-bg "#[0-9a-f]{6}"$`, 'm'), k);
    assert.match(z, new RegExp(`^set ${k}-fg "#[0-9a-f]{6}"$`, 'm'), k);
  }
});

// imv has no include, so the theme renders its whole config, v1's binds with it.
test('the imv config sits the image on paper with the overlay in ink on surface, and keeps v1\'s trash binds', () => {
  const imv = renderImv(blueprint);
  assert.match(imv, /^\[options\]$/m);
  assert.match(imv, /^background = 0c1a2e$/m);
  assert.match(imv, /^overlay_text_color = d6f4f8$/m);
  assert.match(imv, /^overlay_background_color = 0a1526$/m);
  assert.match(imv, /^overlay_font = Maple Mono:14$/m);
  assert.match(imv, /^\[binds\]\n<Ctrl\+x> = exec gio trash -- "\$imv_current_file"; quit\n<Ctrl\+Shift\+X> = exec gio trash -- "\$imv_current_file"; close$/m);
  assert.match(renderImv(paper), /^background = f1e9d8$/m);
});

// wl-kbptr's labels and boxes in the theme's colours and face: ink labels, the typed part in accent, the screen washed in paper.
test('the wl-kbptr config draws its labels in ink and the theme\'s face, picks in accent and washes the screen in paper', () => {
  const k = renderKbptr(blueprint);
  for (const mode of ['tile', 'floating', 'bisect']) {
    const section = k.split(/^(?=\[)/m).find((s) => s.startsWith(`[mode_${mode}]`));
    assert.ok(section, mode);
    assert.match(section, /^label_color=#d6f4f8ff$/m);
    assert.match(section, /^label_font_family=Maple Mono$/m);
    assert.match(section, /^unselectable_bg_color=#0c1a2e99$/m);
  }
  assert.match(k, /^\[mode_floating\]\n(?:.*\n)*?selectable_border_color=#7fe3f0ff$/m);
  assert.match(k, /^label_select_color=#7fe3f0ff$/m);
  assert.match(k, /^pointer_color=#7fe3f0ff$/m);
  assert.doesNotMatch(k, /^\[general\]/m);
  assert.match(renderKbptr(paper), /^unselectable_bg_color=#f1e9d899$/m);
});
