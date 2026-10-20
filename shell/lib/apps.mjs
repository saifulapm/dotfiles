// Renders the per-app fragments (tmux, kak, yazi, fish, GTK, Chromium, and the claude, pi, opencode and amx TUIs) from a validated theme; pure, no object spread.
import { mix } from './notes-look.mjs';

const lower = (s) => s.toLowerCase();
const rgb = (s) => `rgb:${lower(s).slice(1)}`;


// The bar sits on the terminal's own background; the formats carry their colours, as tmux bakes #[...] into a format.
export function renderTmux(t) {
  const c = t.color;
  const [ink, muted, line, surface, paper, accent, danger] = [c.ink, c.muted, c.line, c.surface, c.paper, c.accent, c.danger].map(lower);
  const frame = t.primitive.frame;
  const edge = { ink, double: ink, hairline: muted }[frame] ?? accent;
  const lines = frame === 'double' ? 'double' : 'single';
  // A cut corner draws a tab as a drawing's dimension marks; round and square fill it, round with Nerd Font half circles at its ends.
  const marks = t.primitive.corner === 'cut';
  const [l, r] = t.primitive.corner === 'round' ? ['\ue0b6', '\ue0b4'] : ['', ''];
  const pad = l ? '' : ' ';
  const tab = marks
    ? (mark, text) => `#[fg=${mark}]├─ #[fg=${ink}]${text}#[fg=${mark}] ─┤#[default]`
    : (bg, text) => `#[fg=${bg},bg=default]${l}#[fg=${surface},bg=${bg}]${pad}${text}${pad}#[fg=${bg},bg=default]${r}#[default]`;
  // A plain tab keeps the current one's width, so the centred list does not shift as focus moves.
  const plain = marks
    ? (text) => `   #[fg=${muted}]${text}#[default]   `
    : (text) => `${l && ' '}${pad}#[fg=${muted}]${text}#[default]${pad}${r && ' '}`;
  const win = '#I #W#{?window_zoomed_flag, \u{f0293},}';
  return [
    `set -g status-style "fg=${muted},bg=default"`,
    `set -g status-left " ${tab(`#{?client_prefix,${accent},${marks ? line : ink}}`, '#S')} "`,
    `set -g status-right "#[fg=${accent}]#(amx statusline)#[fg=${muted}] #{?#{==:#{pane_current_path},#{HOME}},~,#{=/-24/…:#{b:pane_current_path}}} "`,
    `set -g window-status-format "${plain(win)}"`,
    `set -g window-status-current-format "${tab(accent, win)}"`,
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
  const faces = [
    ['value', `${rgb(c.danger)}`],
    ['type', `${rgb(c.accent)}`],
    ['variable', `${rgb(c.ok)}`],
    ['module', `${rgb(c.ok)}`],
    ['function', `${rgb(c.accent)}`],
    ['string', `${rgb(c.ok)}`],
    ['keyword', `${rgb(c.accent)}+b`],
    ['operator', `${rgb(c.ink)}`],
    ['attribute', `${rgb(c.danger)}`],
    ['comment', `${rgb(c.muted)}+i`],
    ['documentation', 'comment'],
    ['meta', `${rgb(c.danger)}`],
    ['builtin', `${rgb(c.ink)}+b`],
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
    ['MenuBackground', `${rgb(c.ink)},${rgb(c.line)}`],
    ['MenuInfo', `${rgb(c.muted)}`],
    ['Information', `${rgb(c.surface)},${rgb(c.danger)}`],
    ['Error', `${rgb(c.surface)},${rgb(c.danger)}`],
    ['DiagnosticError', `${rgb(c.danger)}`],
    ['DiagnosticWarning', `${rgb(c.danger)}`],
    ['StatusLine', `${rgb(c.ink)},${rgb(c.line)}`],
    ['StatusLineMode', `${rgb(c.accent)},${rgb(c.line)}+b`],
    ['StatusLineInfo', `${rgb(c.muted)},${rgb(c.line)}`],
    ['StatusLineValue', `${rgb(c.ok)},${rgb(c.line)}`],
    ['StatusCursor', `${rgb(c.surface)},${rgb(c.accent)}`],
    ['Prompt', `${rgb(c.accent)},${rgb(c.line)}`],
    ['MatchingChar', `${rgb(c.ink)},${rgb(c.line)}+b`],
    ['Whitespace', `${rgb(c.line)}+f`],
    ['BufferPadding', `${rgb(c.line)},${rgb(c.surface)}`],
  ];
  return faces.map(([n, v]) => `face global ${n} ${v}`).join('\n') + '\n';
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

export function renderChromium(t) {
  return JSON.stringify({ BrowserThemeColor: lower(t.color.surface), BrowserColorScheme: t.mode }, null, 2) + '\n';
}

// The coding agents draw inside foot, so each sits on surface with ink text; the configs v2 carries from v1 name the theme qshell.
function agentColors(t) {
  const c = t.color;
  const a = c.ansi.map(lower);
  const [ink, muted, line, surface, accent, danger, ok] = [c.ink, c.muted, c.line, c.surface, c.accent, c.danger, c.ok].map(lower);
  const on = (x, share) => mix(surface, x, share);
  return { a, ink, muted, line, surface, accent, danger, ok, on };
}

export function renderClaude(t) {
  const { a, ink, muted, line, surface, accent, danger, ok, on } = agentColors(t);
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
  };
  return JSON.stringify({ name: 'qshell', base: t.mode, overrides }, null, 2) + '\n';
}

// pi's roles point at vars, so a theme only sets the vars.
const PI_COLORS = {
  accent: 'accent', border: 'border', borderAccent: 'accent', borderMuted: 'borderMuted', success: 'color2', error: 'color1',
  warning: 'color3', muted: 'mutedText', dim: 'dimText', text: 'foreground', thinkingText: 'dimText', selectedBg: 'selectedBackground',
  userMessageBg: 'panel', userMessageText: 'foreground', customMessageBg: 'panel', customMessageText: 'foreground',
  customMessageLabel: 'accent', toolPendingBg: 'panelPending', toolSuccessBg: 'panelSuccess', toolErrorBg: 'panelError',
  toolTitle: 'accent', toolOutput: 'foreground', mdHeading: 'color5', mdLink: 'accent', mdLinkUrl: 'color6', mdCode: 'color6',
  mdCodeBlock: 'foreground', mdCodeBlockBorder: 'borderMuted', mdQuote: 'mutedText', mdQuoteBorder: 'borderMuted', mdHr: 'borderMuted',
  mdListBullet: 'color5', toolDiffAdded: 'color2', toolDiffRemoved: 'color1', toolDiffContext: 'mutedText', syntaxComment: 'dimText',
  syntaxKeyword: 'color5', syntaxFunction: 'color4', syntaxVariable: 'accent', syntaxString: 'color2', syntaxNumber: 'color3',
  syntaxType: 'color4', syntaxOperator: 'color5', syntaxPunctuation: 'mutedText', thinkingOff: 'borderMuted', thinkingMinimal: 'accent',
  thinkingLow: 'color4', thinkingMedium: 'color5', thinkingHigh: 'color3', thinkingXhigh: 'color1', bashMode: 'color3',
};

export function renderPi(t) {
  const { a, ink, line, surface, accent, danger, ok, on } = agentColors(t);
  const vars = {
    background: surface, foreground: ink, accent, selectionBackground: line, selectionForeground: ink, selectedBackground: on(accent, 0.22),
    panel: on(ink, 0.06), panelAlt: on(ink, 0.1), panelPending: on(accent, 0.12), panelSuccess: on(ok, 0.12), panelError: on(danger, 0.12),
    border: on(ink, 0.3), borderMuted: on(ink, 0.2), mutedText: mix(ink, surface, 0.34), dimText: mix(ink, surface, 0.52),
  };
  a.forEach((hex, i) => (vars['color' + i] = hex));
  return JSON.stringify({ $schema: 'https://raw.githubusercontent.com/earendil-works/pi/main/packages/coding-agent/src/modes/interactive/theme/theme-schema.json', name: 'qshell', appearance: t.mode, vars, colors: PI_COLORS }, null, 2) + '\n';
}

const OPENCODE_THEME = {
  primary: 'accent', secondary: 'magenta', accent: 'accent', error: 'red', warning: 'yellow', success: 'green', info: 'cyan',
  text: 'fg', textMuted: 'fgMuted', background: 'bg', backgroundPanel: 'bgPanel', backgroundElement: 'bgElement',
  border: 'border', borderActive: 'accent', borderSubtle: 'borderSubtle', diffAdded: 'green', diffRemoved: 'red',
  diffContext: 'fgMuted', diffHunkHeader: 'fgMuted', diffHighlightAdded: 'green', diffHighlightRemoved: 'red',
  diffAddedBg: 'diffAddedBg', diffRemovedBg: 'diffRemovedBg', diffContextBg: 'bgPanel', diffLineNumber: 'fgMuted',
  diffAddedLineNumberBg: 'diffAddedBg', diffRemovedLineNumberBg: 'diffRemovedBg', markdownText: 'fg', markdownHeading: 'magenta',
  markdownLink: 'accent', markdownLinkText: 'cyan', markdownCode: 'cyan', markdownBlockQuote: 'fgMuted', markdownEmph: 'yellow',
  markdownStrong: 'magenta', markdownHorizontalRule: 'borderSubtle', markdownListItem: 'cyan', markdownListEnumeration: 'cyan',
  markdownImage: 'blue', markdownImageText: 'cyan', markdownCodeBlock: 'fg', syntaxComment: 'fgMuted', syntaxKeyword: 'magenta',
  syntaxFunction: 'blue', syntaxVariable: 'accent', syntaxString: 'green', syntaxNumber: 'yellow', syntaxType: 'blue',
  syntaxOperator: 'magenta', syntaxPunctuation: 'fgMuted',
};

export function renderOpencode(t) {
  const { a, ink, muted, line, surface, accent, danger, ok, on } = agentColors(t);
  const defs = {
    bg: surface, bgPanel: on(ink, 0.04), bgElement: on(ink, 0.1), fg: ink, fgMuted: muted, accent,
    red: danger, green: ok, yellow: a[3], blue: a[4], magenta: a[5], cyan: a[6],
    border: on(ink, 0.3), borderSubtle: line, diffAddedBg: on(ok, 0.15), diffRemovedBg: on(danger, 0.15),
  };
  return JSON.stringify({ $schema: 'https://opencode.ai/theme.json', defs, theme: OPENCODE_THEME }, null, 2) + '\n';
}

// amx's theme is six roles, named for what a row means; it re-reads the file when its mtime moves.
export function renderAmx(t) {
  const { a, muted, line, accent, danger, ok } = agentColors(t);
  const roles = [['waiting', a[3]], ['done', ok], ['failed', danger], ['stopped', muted], ['accent', accent], ['cursor', line]];
  return roles.map(([k, v]) => `${k} = "${v}"`).join('\n') + '\n';
}
