// Renders the per-app fragments (tmux, kak, helix, yazi, fish, GTK, Chromium, mpv, zathura, imv, and the claude, pi and amx TUIs) from a validated theme; pure, no object spread.
import { mix } from './notes-look.mjs';

const lower = (s) => s.toLowerCase();
const rgb = (s) => `rgb:${lower(s).slice(1)}`;


// tmux has no case modifier, so the caps voices upper-case a name letter by letter.
const CAPS = 'abcdefghijklmnopqrstuvwxyz'.split('').map((l) => `s/${l}/${l.toUpperCase()}/`).join(';');

// The bar sits at the top and reads as the page's running head, in the margins' voice, with no filled block: Paper's caps and dashes, Artboard's accent dot, Blueprint's brackets.
export function renderTmux(t) {
  const c = t.color;
  const [ink, muted, line, surface, paper, accent, danger] = [c.ink, c.muted, c.line, c.surface, c.paper, c.accent, c.danger].map(lower);
  const frame = t.primitive.frame;
  const edge = { ink, double: ink, hairline: muted }[frame] ?? accent;
  const lines = frame === 'double' ? 'double' : 'single';
  const voice = { plain: 'plain', bracket: 'bracket' }[t.type.voice] ?? 'caps';
  const say = (mods, name) => `#{${[mods, voice === 'plain' ? '' : CAPS].filter((m) => m).join(';')}:${name}}`;
  const number = '#{?#{e|<:#{window_index},10},0,}#{window_index}';
  const name = `${say('', 'window_name')}#{?window_zoomed_flag, \u{f0293},}`;
  const current = {
    caps: `#[fg=${ink},bold]${number}#[nobold] ${name}#[default]`,
    bracket: `#[fg=${accent}][${number}]#[fg=${ink}] ${name}#[default]`,
    plain: `#[fg=${accent}]● #[fg=${ink},bold]${number}#[nobold] ${name}#[default]`,
  }[voice];
  const other = voice === 'bracket' ? `#[fg=${muted}][${number}] ${name}#[default]` : `#[fg=${muted}]${number} ${name}#[default]`;
  const sep = { caps: ' — ', bracket: ' · ', plain: '    ' }[voice];
  // Paper and Artboard raise an alert in the accent; Blueprint in amber, its danger token, as the margins' goal does.
  const alert = voice === 'bracket' ? danger : accent;
  const folder = `#{?#{==:#{pane_current_path},#{HOME}},~,${say('b;=/-24/…', 'pane_current_path')}}`;
  return [
    `set -g status-style "fg=${muted},bg=default"`,
    `set -g status-left " #[fg=#{?client_prefix,${accent},${muted}}]${say('s/^amx-//;=/24/…', 'session_name')}#[default] "`,
    `set -g status-right "#(dots-agents ${voice} ${[muted, alert, ink].map((x) => x.slice(1)).join(' ')})#[fg=${muted}]${folder} "`,
    `set -g window-status-format "${other}"`,
    `set -g window-status-current-format "${current}"`,
    `set -g window-status-separator "#[fg=${muted}]${sep}"`,
    `set -g pane-border-lines ${lines}`,
    `set -g pane-border-style "fg=${line}"`,
    `set -g pane-active-border-style "fg=${edge}"`,
    `set -g popup-border-lines ${t.primitive.corner === 'round' ? 'rounded' : lines}`,
    `set -g popup-border-style "fg=${edge}"`,
    `set -g menu-border-lines ${t.primitive.corner === 'round' ? 'rounded' : lines}`,
    `set -g menu-border-style "fg=${edge}"`,
    `set -g menu-style "fg=${ink},bg=${surface}"`,
    `set -g menu-selected-style "fg=${surface},bg=${accent}"`,
    `set -g message-style "fg=${ink},bg=${paper}"`,
    `set -g message-command-style "fg=${danger},bg=${paper}"`,
    `set -g mode-style "fg=${surface},bg=${accent}"`,
    `set -g copy-mode-match-style "fg=${ink},bg=${line}"`,
    `set -g copy-mode-current-match-style "fg=${surface},bg=${accent}"`,
    `set -g clock-mode-colour "${accent}"`,
    `set -g display-panes-active-colour "${accent}"`,
    `set -g display-panes-colour "${muted}"`,
    '',
  ].join('\n');
}

export function renderKak(t) {
  const c = t.color;
  const s = t.syntax;
  // Menus sit on a light wash of ink; info boxes, framed by their border, and the status line are flat, as tmux's bar is.
  const tint = mix(c.surface, c.ink, 0.06);
  const faces = [
    ['value', `${rgb(s.value)}`],
    ['type', `${rgb(s.type)}`],
    ['variable', `${rgb(s.variable)}`],
    ['module', `${rgb(s.type)}`],
    ['function', `${rgb(s.function)}`],
    ['string', `${rgb(s.string)}`],
    ['keyword', `${rgb(s.keyword)}+b`],
    ['operator', `${rgb(c.ink)}`],
    ['attribute', `${rgb(s.attribute)}`],
    ['comment', `${rgb(s.comment)}+i`],
    ['documentation', 'comment'],
    ['meta', `${rgb(s.meta)}`],
    ['builtin', `${rgb(s.builtin)}+b`],
    ['title', `${rgb(c.accent)}+b`],
    ['header', `${rgb(c.accent)}`],
    ['mono', `${rgb(c.ok)}`],
    ['block', `${rgb(c.danger)}`],
    ['link', `${rgb(c.accent)}+u`],
    ['bullet', `${rgb(c.accent)}`],
    ['list', `${rgb(c.ink)}`],
    ['Default', `${rgb(c.ink)},${rgb(c.surface)}`],
    ['PrimarySelection', `${rgb(c.surface)},${rgb(c.accent)}+fg`],
    ['SecondarySelection', `${rgb(c.surface)},${rgb(c.muted)}+fg`],
    ['PrimaryCursor', `${rgb(c.surface)},${rgb(c.ink)}+fg`],
    ['SecondaryCursor', `${rgb(c.surface)},${rgb(c.muted)}+fg`],
    ['PrimaryCursorEol', `${rgb(c.surface)},${rgb(c.danger)}+fg`],
    ['SecondaryCursorEol', `${rgb(c.surface)},${rgb(c.muted)}+fg`],
    ['LineNumbers', `${rgb(c.muted)},${rgb(c.surface)}`],
    ['LineNumberCursor', `${rgb(c.accent)},${rgb(c.surface)}+b`],
    ['LineNumbersWrapped', `${rgb(c.line)},${rgb(c.surface)}+i`],
    ['MenuForeground', `${rgb(c.surface)},${rgb(c.accent)}`],
    ['MenuBackground', `${rgb(c.ink)},${rgb(tint)}`],
    ['MenuInfo', `${rgb(c.muted)}`],
    ['Information', `${rgb(c.ink)},${rgb(c.surface)}`],
    ['Error', `${rgb(c.surface)},${rgb(c.danger)}`],
    ['DiagnosticError', `${rgb(c.danger)}`],
    ['DiagnosticWarning', `${rgb(c.danger)}`],
    ['StatusLine', `${rgb(c.ink)},${rgb(c.surface)}`],
    ['StatusLineMode', `${rgb(c.accent)},${rgb(c.surface)}+b`],
    ['StatusLineInfo', `${rgb(c.muted)},${rgb(c.surface)}`],
    ['StatusLineValue', `${rgb(c.ok)},${rgb(c.surface)}`],
    ['StatusCursor', `${rgb(c.surface)},${rgb(c.accent)}`],
    ['Prompt', `${rgb(c.accent)},${rgb(c.surface)}`],
    ['MatchingChar', `${rgb(c.ink)},${rgb(c.line)}+b`],
    ['Whitespace', `${rgb(c.line)}+f`],
    ['BufferPadding', `${rgb(c.line)},${rgb(c.surface)}`],
  ];
  return faces.map(([n, v]) => `face global ${n} ${v}`).join('\n') + '\n';
}

// helix takes kak's look: the theme's syntax table, a flat status line, and menus and popups on the same light wash of ink, since helix draws them without a border.
export function renderHelix(t) {
  const c = t.color;
  const s = t.syntax;
  const a = c.ansi.map(lower);
  const [ink, muted, line, surface, accent, danger, ok] = [c.ink, c.muted, c.line, c.surface, c.accent, c.danger, c.ok].map(lower);
  const tint = mix(surface, ink, 0.06);
  const x = (k) => lower(s[k]);
  const style = (fg, bg, ...mods) => {
    const parts = [];
    if (fg) parts.push(`fg = "${fg}"`);
    if (bg) parts.push(`bg = "${bg}"`);
    if (mods.length) parts.push(`modifiers = [${mods.map((m) => `"${m}"`).join(', ')}]`);
    return `{ ${parts.join(', ')} }`;
  };
  const curl = (color) => `{ underline = { color = "${color}", style = "curl" } }`;
  const scopes = [
    ['ui.background', style(null, surface)],
    ['ui.text', `"${ink}"`],
    ['ui.text.focus', style(ink, tint)],
    ['ui.text.inactive', `"${muted}"`],
    ['ui.text.info', `"${ink}"`],
    ['ui.cursor', style(surface, muted)],
    ['ui.cursor.primary', style(surface, ink)],
    ['ui.cursor.match', style(ink, line, 'bold')],
    ['ui.selection', style(surface, muted)],
    ['ui.selection.primary', style(surface, accent)],
    ['ui.cursorline.primary', style(null, tint)],
    ['ui.linenr', `"${muted}"`],
    ['ui.linenr.selected', style(accent, null, 'bold')],
    ['ui.statusline', style(ink, surface)],
    ['ui.statusline.inactive', style(muted, surface)],
    ['ui.statusline.normal', style(accent, surface, 'bold')],
    ['ui.statusline.insert', style(ok, surface, 'bold')],
    ['ui.statusline.select', style(a[5], surface, 'bold')],
    ['ui.bufferline', style(muted, surface)],
    ['ui.bufferline.active', style(ink, surface, 'bold')],
    ['ui.popup', style(ink, tint)],
    ['ui.help', style(ink, tint)],
    ['ui.menu', style(ink, tint)],
    ['ui.menu.selected', style(surface, accent)],
    ['ui.window', `"${line}"`],
    ['ui.highlight', style(null, tint)],
    ['ui.virtual.whitespace', `"${line}"`],
    ['ui.virtual.indent-guide', `"${line}"`],
    ['ui.virtual.ruler', style(null, tint)],
    ['ui.virtual.inlay-hint', `"${muted}"`],
    ['ui.virtual.jump-label', style(accent, null, 'bold')],
    ['error', `"${danger}"`],
    ['warning', `"${a[3]}"`],
    ['info', `"${a[4]}"`],
    ['hint', `"${muted}"`],
    ['diagnostic.error', curl(danger)],
    ['diagnostic.warning', curl(a[3])],
    ['diagnostic.info', curl(a[4])],
    ['diagnostic.hint', curl(muted)],
    ['diagnostic.unnecessary', style(null, null, 'dim')],
    ['diagnostic.deprecated', style(null, null, 'crossed_out')],
    ['diff.plus', `"${ok}"`],
    ['diff.minus', `"${danger}"`],
    ['diff.delta', `"${a[3]}"`],
    ['keyword', style(x('keyword'), null, 'bold')],
    ['function', `"${x('function')}"`],
    ['function.builtin', `"${x('builtin')}"`],
    ['constructor', `"${x('function')}"`],
    ['string', `"${x('string')}"`],
    ['string.regexp', `"${x('meta')}"`],
    ['string.special', `"${x('meta')}"`],
    ['type', `"${x('type')}"`],
    ['type.builtin', `"${x('builtin')}"`],
    ['namespace', `"${x('type')}"`],
    ['constant', `"${x('value')}"`],
    ['constant.builtin', `"${x('builtin')}"`],
    ['variable', `"${x('variable')}"`],
    ['variable.builtin', `"${x('builtin')}"`],
    ['attribute', `"${x('attribute')}"`],
    ['tag', `"${x('keyword')}"`],
    ['label', `"${x('meta')}"`],
    ['special', `"${x('meta')}"`],
    ['comment', style(x('comment'), null, 'italic')],
    ['operator', `"${ink}"`],
    ['punctuation', `"${ink}"`],
    ['markup.heading', style(accent, null, 'bold')],
    ['markup.list', `"${accent}"`],
    ['markup.bold', style(null, null, 'bold')],
    ['markup.italic', style(null, null, 'italic')],
    ['markup.strikethrough', style(null, null, 'crossed_out')],
    ['markup.link.url', style(accent, null, 'underlined')],
    ['markup.link.text', `"${accent}"`],
    ['markup.raw', `"${ok}"`],
    ['markup.quote', style(x('comment'), null, 'italic')],
  ];
  return scopes.map(([k, v]) => `"${k}" = ${v}`).join('\n') + '\n';
}

// yazi's names for ANSI slots 0-15; a token equal to a slot is named so a live palette change recolours a running yazi.
const YAZI_ANSI = ['black', 'red', 'green', 'yellow', 'blue', 'magenta', 'cyan', 'gray', 'darkgray', 'lightred', 'lightgreen', 'lightyellow', 'lightblue', 'lightmagenta', 'lightcyan', 'white'];

export function renderYazi(t) {
  const c = t.color;
  const slots = c.ansi.map(lower);
  const name = (hex) => { const i = slots.indexOf(lower(hex)); return i < 0 ? lower(hex) : YAZI_ANSI[i]; };
  const [ink, muted, line, accent, danger, ok] = [c.ink, c.muted, c.line, c.accent, c.danger, c.ok].map(name);
  // Foot paints the terminal background in surface, so reset follows it live.
  const surface = lower(c.surface);
  return [
    '[mgr]',
    `cwd = { fg = "${accent}" }`,
    `hovered = { fg = "${surface}", bg = "${accent}" }`,
    `border_style = { fg = "${line}" }`,
    `tab_active = { fg = "${surface}", bg = "${accent}" }`,
    `tab_inactive = { fg = "${ink}", bg = "${line}" }`,
    `marker_selected = { fg = "${ok}", bg = "${ok}" }`,
    `count_selected = { fg = "${surface}", bg = "${ok}" }`,
    '',
    '[mode]',
    `normal_main = { fg = "${surface}", bg = "${accent}", bold = true }`,
    `normal_alt = { fg = "${accent}", bg = "${line}" }`,
    `select_main = { fg = "${surface}", bg = "${ok}", bold = true }`,
    `select_alt = { fg = "${ok}", bg = "${line}" }`,
    `unset_main = { fg = "${surface}", bg = "${danger}", bold = true }`,
    `unset_alt = { fg = "${danger}", bg = "${line}" }`,
    '',
    '[status]',
    `overall = { fg = "${muted}", bg = "reset" }`,
    '',
  ].join('\n');
}

export function renderFish(t) {
  const c = t.color;
  const [ink, muted, line, surface, accent, danger, ok] = [c.ink, c.muted, c.line, c.surface, c.accent, c.danger, c.ok].map(lower);
  const bare = (s) => s.slice(1);
  const colors = [
    ['normal', ink], ['command', accent], ['keyword', accent], ['quote', ok], ['redirection', ink], ['end', muted],
    ['error', danger], ['param', ink], ['comment', muted], ['operator', accent], ['escape', danger], ['autosuggestion', muted],
    ['cwd', accent], ['status', danger],
    ['selection', `--background=${bare(line)}`], ['search_match', `--background=${bare(line)}`],
  ];
  const lines = colors.map(([n, v]) => `set -g fish_color_${n} ${v.startsWith('#') ? bare(v) : v}`);
  const fzf = `--color=fg:${ink},bg:${surface},hl:${accent},fg+:${ink},bg+:${line},hl+:${accent},info:${muted},prompt:${accent},pointer:${accent},marker:${ok},spinner:${accent},header:${muted}`;
  lines.push(`set -gx FZF_DEFAULT_OPTS "${fzf}"`);
  return lines.join('\n') + '\n';
}

export function renderGtkCss(t) {
  const c = t.color;
  const defs = [
    ['window_bg_color', c.paper], ['window_fg_color', c.ink],
    ['view_bg_color', c.surface], ['view_fg_color', c.ink],
    ['headerbar_bg_color', c.surface], ['headerbar_fg_color', c.ink],
    ['accent_bg_color', c.accent], ['accent_fg_color', c.surface], ['accent_color', c.accent],
    ['theme_bg_color', c.paper], ['theme_fg_color', c.ink],
    ['theme_base_color', c.surface], ['theme_text_color', c.ink],
    ['theme_selected_bg_color', c.accent], ['theme_selected_fg_color', c.surface],
  ];
  return defs.map(([n, v]) => `@define-color ${n} ${lower(v)};`).join('\n') + '\n';
}

export function renderGtkSettings(t) {
  return `[Settings]\ngtk-application-prefer-dark-theme=${t.mode === 'dark'}\ngtk-font-name=${t.type.ui} 11\n`;
}

// Chromium loads this theme extension at its start; a BrowserThemeColor policy would block it, so the theme carries no policy.
export function renderChromiumTheme(t) {
  const c = t.color;
  const rgb3 = (hex) => [1, 3, 5].map((i) => parseInt(hex.slice(i, i + 2), 16));
  const [ink, muted, paper, surface, accent] = [c.ink, c.muted, c.paper, c.surface, c.accent].map(rgb3);
  const colors = {
    frame: paper, frame_inactive: paper, background_tab: paper, toolbar: surface, toolbar_text: ink, toolbar_button_icon: ink,
    tab_text: ink, tab_background_text: muted, bookmark_text: ink, omnibox_background: paper, omnibox_text: ink,
    ntp_background: paper, ntp_text: ink, ntp_link: accent,
  };
  return JSON.stringify({ manifest_version: 3, name: 'dots', version: '1', description: `The ${t.name} theme`, theme: { colors } }, null, 2) + '\n';
}

// mpv.conf includes this; the OSC sits on surface with ink controls and holds a pressed control in the accent.
function mpvOptions(t) {
  const c = t.color;
  const [ink, surface, accent] = [c.ink, c.surface, c.accent].map(lower);
  const osc = [
    ['background_color', surface], ['timecode_color', ink], ['title_color', ink], ['time_pos_color', ink], ['time_pos_outline_color', surface],
    ['buttons_color', ink], ['top_buttons_color', ink], ['small_buttonsL_color', ink], ['small_buttonsR_color', ink], ['held_element_color', accent],
  ];
  const opts = [['osd-color', ink], ['osd-back-color', surface], ['osd-border-color', surface], ['osd-font', t.type.ui], ['sub-font', t.type.display]];
  for (const [k, v] of osc) opts.push(['script-opts-append', `osc-${k}=${v}`]);
  return opts;
}

// mpv reads # as a comment, so each value is quoted.
export function renderMpv(t) {
  return mpvOptions(t).map(([k, v]) => `${k}="${v}"`).join('\n') + '\n';
}

// The same options as IPC commands, one per line, which dots theme sends each open player.
export function renderMpvIpc(t) {
  const cmd = ([k, v]) => (k === 'script-opts-append' ? ['change-list', 'script-opts', 'append', v] : ['set_property', k, v]);
  return mpvOptions(t).map((o) => JSON.stringify({ command: cmd(o) })).join('\n') + '\n';
}

// zathurarc includes this. Dark themes recolour the page into paper and ink, keeping image hues; a light theme says recolor false, since a re-source keeps any option it does not name.
export function renderZathura(t) {
  const c = t.color;
  const [ink, muted, paper, surface, accent, danger] = [c.ink, c.muted, c.paper, c.surface, c.accent, c.danger].map(lower);
  const pairs = [
    ['default', paper, ink], ['statusbar', surface, ink], ['inputbar', surface, ink], ['index', paper, ink], ['index-active', accent, surface],
    ['completion', surface, ink], ['completion-group', paper, muted], ['completion-highlight', accent, surface],
    ['notification', surface, ink], ['notification-error', danger, surface], ['notification-warning', accent, surface],
  ];
  const lines = [];
  for (const [k, bg, fg] of pairs) lines.push(`set ${k}-bg "${bg}"`, `set ${k}-fg "${fg}"`);
  lines.push(`set highlight-color "${accent}"`, `set highlight-active-color "${danger}"`, `set font "${t.type.ui} 11"`);
  const dark = t.mode === 'dark';
  lines.push(`set recolor ${dark}`, `set recolor-keephue ${dark}`, `set recolor-lightcolor "${paper}"`, `set recolor-darkcolor "${ink}"`);
  return lines.join('\n') + '\n';
}

// imv has no include, so this is its whole config, v1's trash binds with it; dots theme changes an open window's background, and the overlay takes its colours at imv's next start.
export function renderImv(t) {
  const c = t.color;
  const [ink, paper, surface] = [c.ink, c.paper, c.surface].map((x) => lower(x).slice(1));
  return [
    '[options]', `background = ${paper}`, `overlay_font = ${t.type.ui}:14`, `overlay_text_color = ${ink}`, `overlay_background_color = ${surface}`, '',
    '[binds]', '<Ctrl+x> = exec gio trash -- "$imv_current_file"; quit', '<Ctrl+Shift+X> = exec gio trash -- "$imv_current_file"; close', '',
  ].join('\n');
}

// The coding agents draw inside foot, so each sits on surface with ink text; Claude Code, pi and amx name the theme dots.
function agentColors(t) {
  const c = t.color;
  const a = c.ansi.map(lower);
  const [ink, muted, line, surface, accent, danger, ok] = [c.ink, c.muted, c.line, c.surface, c.accent, c.danger, c.ok].map(lower);
  const on = (x, share) => mix(surface, x, share);
  return { a, ink, muted, line, surface, accent, danger, ok, on };
}

export function renderClaude(t) {
  const { a, ink, muted, line, surface, accent, danger, ok, on } = agentColors(t);
  const shimmer = (x) => mix(x, ink, 0.35);
  const orange = mix(a[1], a[3], 0.5);
  const overrides = {
    claude: accent, claudeShimmer: mix(accent, ink, 0.35), text: ink, inverseText: surface,
    inactive: mix(ink, surface, 0.4), inactiveShimmer: mix(ink, surface, 0.25), subtle: muted,
    suggestion: a[6], permission: a[4], permissionShimmer: mix(a[4], ink, 0.35), remember: a[3],
    success: ok, error: danger, warning: a[3], warningShimmer: mix(a[3], ink, 0.35), merged: a[5],
    promptBorder: accent, promptBorderShimmer: mix(accent, ink, 0.35), planMode: a[6], autoAccept: a[3],
    bashBorder: a[11], ide: a[14],
    diffAdded: on(ok, 0.15), diffRemoved: on(danger, 0.15), diffAddedDimmed: on(ok, 0.08), diffRemovedDimmed: on(danger, 0.08),
    diffAddedWord: on(ok, 0.32), diffRemovedWord: on(danger, 0.32),
    userMessageBackground: on(ink, 0.06), userMessageBackgroundHover: on(ink, 0.1),
    bashMessageBackgroundColor: on(ink, 0.06), memoryBackgroundColor: on(ink, 0.06), selectionBg: line,
    rate_limit_fill: accent, rate_limit_empty: on(ink, 0.2), briefLabelYou: a[3], briefLabelClaude: accent,
    autoAcceptShimmer: shimmer(a[3]), skill: a[5], effortUltra: a[5], fastMode: orange, fastModeShimmer: shimmer(orange),
    claudeBlue_FOR_SYSTEM_SPINNER: a[4], claudeBlueShimmer_FOR_SYSTEM_SPINNER: shimmer(a[4]), background: a[6], professionalBlue: a[4],
    chromeYellow: a[3], clawd_body: accent, clawd_background: surface, composerSidebarBackground: on(ink, 0.06),
  };
  // Subagents and the rainbow take the ANSI hues, with orange, pink and indigo mixed from their neighbours.
  const hues = { red: a[1], orange, yellow: a[3], green: a[2], blue: a[4], indigo: mix(a[4], a[5], 0.5), violet: a[5], purple: a[5], pink: mix(a[1], a[5], 0.5), cyan: a[6] };
  for (const k of ['red', 'blue', 'green', 'yellow', 'purple', 'orange', 'pink', 'cyan']) overrides[`${k}_FOR_SUBAGENTS_ONLY`] = hues[k];
  for (const k of ['red', 'orange', 'yellow', 'green', 'blue', 'indigo', 'violet']) {
    overrides[`rainbow_${k}`] = hues[k];
    overrides[`rainbow_${k}_shimmer`] = shimmer(hues[k]);
  }
  return JSON.stringify({ name: 'dots', base: t.mode, overrides }, null, 2) + '\n';
}

// pi's roles point at vars, so a theme only sets the vars.
const PI_COLORS = {
  accent: 'accent', border: 'border', borderAccent: 'accent', borderMuted: 'borderMuted', success: 'color2', error: 'color1',
  warning: 'color3', muted: 'mutedText', dim: 'dimText', text: 'foreground', thinkingText: 'dimText', selectedBg: 'selectedBackground',
  userMessageBg: 'panel', userMessageText: 'foreground', customMessageBg: 'panel', customMessageText: 'foreground',
  customMessageLabel: 'accent', toolPendingBg: 'panelPending', toolSuccessBg: 'panelSuccess', toolErrorBg: 'panelError',
  toolTitle: 'accent', toolOutput: 'foreground', mdHeading: 'color5', mdLink: 'accent', mdLinkUrl: 'color6', mdCode: 'color6',
  mdCodeBlock: 'foreground', mdCodeBlockBorder: 'borderMuted', mdQuote: 'mutedText', mdQuoteBorder: 'borderMuted', mdHr: 'borderMuted',
  mdListBullet: 'color5', toolDiffAdded: 'color2', toolDiffRemoved: 'color1', toolDiffContext: 'mutedText', syntaxComment: 'synComment',
  syntaxKeyword: 'synKeyword', syntaxFunction: 'synFunction', syntaxVariable: 'synVariable', syntaxString: 'synString', syntaxNumber: 'synValue',
  syntaxType: 'synType', syntaxOperator: 'foreground', syntaxPunctuation: 'mutedText', thinkingOff: 'borderMuted', thinkingMinimal: 'accent',
  thinkingLow: 'color4', thinkingMedium: 'color5', thinkingHigh: 'color3', thinkingXhigh: 'color1', thinkingMax: 'color9', bashMode: 'color3',
  scrollbarTrack: 'panelAlt', scrollbarThumb: 'border', searchMatchBg: 'highlight', searchMatchText: 'foreground',
};
const PI_EXPORT = { pageBg: 'background', cardBg: 'panel', infoBg: 'highlight' };

export function renderPi(t) {
  const { a, ink, line, surface, accent, danger, ok, on } = agentColors(t);
  const vars = {
    background: surface, foreground: ink, accent, selectionBackground: line, selectionForeground: ink, selectedBackground: on(accent, 0.22),
    panel: on(ink, 0.06), panelAlt: on(ink, 0.1), panelPending: on(accent, 0.12), panelSuccess: on(ok, 0.12), panelError: on(danger, 0.12),
    border: on(ink, 0.3), borderMuted: on(ink, 0.2), mutedText: mix(ink, surface, 0.34), dimText: mix(ink, surface, 0.39), highlight: on(a[3], 0.2),
  };
  a.forEach((hex, i) => (vars['color' + i] = hex));
  // Code takes the theme's syntax table, as kak and helix do.
  for (const k of ['comment', 'keyword', 'function', 'variable', 'string', 'value', 'type']) vars['syn' + k[0].toUpperCase() + k.slice(1)] = lower(t.syntax[k]);
  return JSON.stringify({ $schema: 'https://pi.dev/schemas/theme.schema.json', name: 'dots', appearance: t.mode, vars, colors: PI_COLORS, export: PI_EXPORT }, null, 2) + '\n';
}

// amx's theme is six roles, named for what a row means; it re-reads the file when its mtime moves.
export function renderAmx(t) {
  const { a, muted, line, accent, danger, ok } = agentColors(t);
  const roles = [['waiting', a[3]], ['done', ok], ['failed', danger], ['stopped', muted], ['accent', accent], ['cursor', line]];
  return roles.map(([k, v]) => `${k} = "${v}"`).join('\n') + '\n';
}
