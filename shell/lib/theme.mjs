// Validates the one design's theme document, as colorscheme.mjs builds it (Artboard's dots, an ink frame, no shadow, square, the spring, Maple Mono in the plain voice), and renders its fragments; pure, so the shell can import it too.
const DESIGN = { paper: 'dots', frame: 'line', shadow: 'none', corner: 'square', motion: 'spring' };
const COLORS = ['paper', 'ink', 'muted', 'line', 'surface', 'accent', 'danger', 'ok'];
const SYNTAX = ['keyword', 'function', 'string', 'type', 'value', 'variable', 'attribute', 'meta', 'builtin', 'comment'];
const FONT = 'Maple Mono';
const HEX = /^#[0-9A-Fa-f]{6}$/;
const HEXA = /^#[0-9A-Fa-f]{6}([0-9A-Fa-f]{2})?$/;
const TAB_SIDES = ['left', 'right', 'top', 'bottom'];

export function validateTheme(doc) {
  const fail = (msg) => { throw new Error(`theme: ${msg}`); };
  const meta = doc.meta ?? fail('missing [meta]');
  if (!meta.name) fail('meta.name is missing');
  if (meta.mode !== 'light' && meta.mode !== 'dark') fail(`meta.mode: "${meta.mode}" is not light or dark`);
  const color = doc.color ?? fail('missing [color]');
  for (const k of COLORS) if (!HEX.test(color[k] ?? '')) fail(`color.${k}: "${color[k]}" is not #RRGGBB`);
  if (!Array.isArray(color.ansi) || color.ansi.length !== 16 || !color.ansi.every((c) => HEX.test(c))) {
    fail('color.ansi must hold 16 #RRGGBB colours');
  }
  const syntax = doc.syntax ?? fail('missing [syntax]');
  for (const k of SYNTAX) if (!HEX.test(syntax[k] ?? '')) fail(`syntax.${k}: "${syntax[k]}" is not #RRGGBB`);
  const primitive = doc.primitive ?? fail('missing [primitive]');
  for (const [k, v] of Object.entries(DESIGN)) if (primitive[k] !== v) fail(`primitive.${k}: "${primitive[k]}" is not ${v}, the one design's`);
  const type = doc.type ?? fail('missing [type]');
  for (const k of ['display', 'ui', 'mono']) if (type[k] !== FONT) fail(`type.${k}: "${type[k]}" is not ${FONT}`);
  if (type.voice !== 'plain') fail(`type.voice: "${type.voice}" is not plain`);
  const niri = doc.niri ?? fail('missing [niri]');
  if ('border_inactive' in niri && !HEXA.test(niri.border_inactive)) fail(`niri.border_inactive: "${niri.border_inactive}" is not #RRGGBB or #RRGGBBAA`);
  if ('tab_position' in niri && !TAB_SIDES.includes(niri.tab_position)) fail(`niri.tab_position: "${niri.tab_position}" is not one of ${TAB_SIDES.join(', ')}`);
  return {
    name: meta.name,
    mode: meta.mode,
    color: Object.assign({}, color, { ansi: [...color.ansi] }),
    syntax: Object.assign({}, syntax),
    primitive: Object.assign({}, primitive),
    paper: Object.assign({}, doc.paper),
    type: { display: type.display, ui: type.ui, mono: type.mono, voice: type.voice, scale: type.scale ?? 1 },
    niri: Object.assign({}, niri, { gaps: niri.gaps ?? 16, border: niri.border ?? 1 }),
  };
}

// The tokens as Qt reads them; every colour is #RRGGBB, so this is a copy.
export const qtTokens = (t) => Object.assign({}, t, { color: Object.assign({}, t.color) });

// The WCAG contrast ratio of two #RRGGBB colours.
export function contrast(a, b) {
  const lum = (hex) => {
    const [r, g, bl] = [1, 3, 5].map((i) => parseInt(hex.slice(i, i + 2), 16) / 255)
      .map((v) => (v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4));
    return 0.2126 * r + 0.7152 * g + 0.0722 * bl;
  };
  const [hi, lo] = [lum(a), lum(b)].sort((x, y) => y - x);
  return (hi + 0.05) / (lo + 0.05);
}

// The shell's tokens come from shell.json, so they get the same check as the render.
export const checkTokens = (t) => validateTheme(Object.assign({}, t, { meta: { name: t.name, mode: t.mode } }));

// niri reads the damping as a float, so a whole one is written 1.0.
const spring = (d, k) => `spring damping-ratio=${Number.isInteger(d) ? d.toFixed(1) : d} stiffness=${k} epsilon=0.0001`;
const eased = (ms, curve) => `duration-ms ${ms}\n        curve "${curve}"`;
// Every animation's timing. A window inks in and out on a short ease, the close quicker so it feels instant; whatever moves a tile is critically damped, since a bounce would open a seam between two sections of the canvas.
const MOTION = {
  'window-open': eased(240, 'ease-out-cubic'),
  'window-close': eased(140, 'ease-out-quad'),
  'workspace-switch': spring(1.0, 600),
  'horizontal-view-movement': spring(1.0, 700),
  'window-movement': spring(1.0, 600),
  'window-resize': spring(1.0, 600),
  'overview-open-close': spring(1.0, 600),
  'screenshot-ui-open': eased(200, 'ease-out-cubic'),
  'config-notification-open-close': spring(0.6, 1000),
  'exit-confirmation-open-close': spring(0.6, 1000),
};

// niri draws the whole tile into niri_tex, border, ring and shadow included, so a shader samples it past the geometry and stops only at the texture's edge.
const TEX = `vec4 dots_tex(vec3 coords_geo) {
    vec3 t = niri_geo_to_tex * coords_geo;
    if (t.x < 0.0 || t.x > 1.0 || t.y < 0.0 || t.y > 1.0) return vec4(0.0);
    return texture2D(niri_tex, t.st);
}`;

// The open and close shaders: a window is part of the canvas, so it inks in and out in place, at its own size, along the field's diagonal from top left to bottom right; s is a pixel's place on that diagonal, e the soft edge's, 0.35 of it wide.
const SHADERS = {
    open: `${TEX}
vec4 open_color(vec3 coords_geo, vec3 size_geo) {
    float s = (coords_geo.x + coords_geo.y) * 0.5;
    float e = niri_clamped_progress * 1.35;
    return dots_tex(coords_geo) * (1.0 - smoothstep(e - 0.35, e, s));
}`,
    close: `${TEX}
vec4 close_color(vec3 coords_geo, vec3 size_geo) {
    float s = (coords_geo.x + coords_geo.y) * 0.5;
    float e = niri_clamped_progress * 1.35;
    return dots_tex(coords_geo) * smoothstep(e - 0.35, e, s);
}`,
};

const indent = (text, pad) => text.split('\n').map((l) => (l ? pad + l : l)).join('\n');

export function renderNiri(t) {
  const c = t.color;
  const n = t.niri;
  // Tabs take the focus colour and the inactive frame's colour.
  const tabs = n.tab_position
    ? [
      'tab-indicator {', '        hide-when-single-tab', '        place-within-column', `        gap ${n.tab_gap}`, `        width ${n.tab_width}`,
      `        length total-proportion=${Number.isInteger(n.tab_length) ? n.tab_length.toFixed(1) : n.tab_length}`, `        position "${n.tab_position}"`, `        gaps-between-tabs ${n.tab_gaps}`,
      '        corner-radius 0',
      `        active-color "${c.ink}"`, `        inactive-color "${n.border_inactive ?? c.muted}"`,
      `        urgent-color "${c.danger}"`, '    }',
    ].join('\n')
    : 'tab-indicator {\n        hide-when-single-tab\n    }';
  const shader = (name) => {
    const glsl = SHADERS[{ 'window-open': 'open', 'window-close': 'close' }[name]];
    return glsl ? `\n        custom-shader r"\n${indent(glsl, '            ')}\n        "` : '';
  };
  const animations = Object.entries(MOTION).map(([name, timing]) => `    ${name} {\n        ${timing}${shader(name)}\n    }`).join('\n');
  // Only the focused window shows an edge, a 1 px line in the dots' own colour, so its size reads as it resizes; the rest stay frameless, one canvas.
  return `layout {
    gaps ${t.niri.gaps}
    background-color "${c.paper}"
    focus-ring {
        off
    }
    border {
        on
        width 1
        active-color "${t.paper?.dot ?? c.line}"
        inactive-color "#00000000"
    }
    shadow {
        off
    }
    ${tabs}
    insert-hint {
        color "${c.accent}80"
    }
    // Windows start 56 px down and 32 px in, below the margins, as on the approved artboard.
    struts {
        top ${56 - t.niri.gaps}
        bottom ${28 - t.niri.gaps}
        left ${32 - t.niri.gaps}
        right ${32 - t.niri.gaps}
    }
}

prefer-no-csd

// niri shows the overview's backdrop between two workspaces while it switches them.
overview {
    backdrop-color "${c.paper}"
}

// The Alt+Tab switcher's highlight wears the scheme. Its binds sit in binds.kdl, since niri merges this section only across includes.
recent-windows {
    highlight {
        active-color "${c.accent}"
        urgent-color "${c.danger}"
        padding 16
        corner-radius 0
    }
}

window-rule {
    geometry-corner-radius 0
    clip-to-geometry true
    draw-border-with-background false
}

// A floating window sits over other windows, so a hard shadow drawn behind it backs its clear ground in the paper, a touch clear itself (97%), so a window under it reads only as a shade; a 1 px gradient of the accent fading into the paper edges it, dimmer when it is not focused.
window-rule {
    match is-floating=true
    draw-border-with-background false
    border {
        on
        width 1
        active-gradient from="${n.edge.from}" to="${n.edge.to}" angle=135
        inactive-gradient from="${n.edge.dimFrom}" to="${n.edge.dimTo}" angle=135
    }
    shadow {
        on
        softness 0
        spread 0
        offset x=0 y=0
        draw-behind-window true
        color "${c.paper}F7"
        inactive-color "${c.paper}F7"
    }
}

// A video is never see-through: its back is solid paper.
window-rule {
    match app-id="^mpv$"
    match app-id="^imv$"
    match title=r#"Picture.?in.?[Pp]icture"#
    shadow {
        color "${c.paper}FF"
        inactive-color "${c.paper}FF"
    }
}

animations {
${animations}
}
`;
}

// [section, key, value] for foot. The palette goes in the theme's own mode section, so foot tells apps truly whether it is light or dark.
function footEntries(t) {
  const hex = (s) => s.slice(1).toUpperCase();
  const pair = (fg, bg) => `${hex(fg)} ${hex(bg)}`;
  const c = t.color;
  const s = `colors-${t.mode}`;
  // The terminal's ground is clear, so its words sit on the desk's field and side-by-side terminals read as one canvas; matching clears an app's cells painted in the ground too.
  const entries = [['main', 'initial-color-theme', t.mode], [s, 'background', hex(c.surface)], [s, 'alpha', '0.0'], [s, 'alpha-mode', 'matching'], [s, 'foreground', hex(c.ink)]];
  c.ansi.forEach((v, i) => entries.push([s, `${i < 8 ? 'regular' : 'bright'}${i % 8}`, hex(v)]));
  entries.push(
    [s, 'cursor', pair(c.surface, c.accent)],
    [s, 'selection-foreground', hex(c.surface)],
    [s, 'selection-background', hex(c.accent)],
    [s, 'urls', hex(c.accent)],
    [s, 'jump-labels', pair(c.surface, c.accent)],
    [s, 'scrollback-indicator', pair(c.surface, c.accent)],
    [s, 'search-box-match', pair(c.surface, c.ink)],
    [s, 'search-box-no-match', pair(c.surface, c.danger)],
  );
  return entries;
}

export function renderFoot(t) {
  const lines = [];
  let section;
  for (const [s, k, v] of footEntries(t)) {
    if (s !== section) lines.push(`[${(section = s)}]`);
    lines.push(`${k}=${v}`);
  }
  return lines.join('\n') + '\n';
}

// One footclient -o override per line: the foot server read foot.ini when it started, so each new window brings the current theme.
export function renderFootArgs(t) {
  return footEntries(t).map(([s, k, v]) => `${s}.${k}=${v}`).join('\n') + '\n';
}

// Written to an open foot's pty, so it recolours without a restart (foot-ctlseqs(7): OSC 4, 10, 11, 12, 17, 19).
export function renderFootOsc(t) {
  const osc = (body) => `\x1b]${body}\x1b\\`;
  const c = t.color;
  return c.ansi.map((v, i) => osc(`4;${i};${v}`)).join('') + osc(`12;${c.accent}`) + osc(`17;${c.accent}`) + osc(`19;${c.surface}`)
    + osc(`10;${c.ink}`) + osc(`11;${c.surface}`);
}
