// Validates a parsed theme.toml and renders its fragments; pure, so the shell can import it too.
const MENUS = {
  paper: ['flat', 'grain', 'dots', 'grid', 'gradient'],
  frame: ['hairline', 'ink', 'double', 'none', 'glow'],
  shadow: ['soft', 'hard-offset', 'none'],
  corner: ['round', 'square', 'cut'],
  motion: ['spring', 'snappy', 'ease', 'typewriter', 'linear'],
};
const COLORS = ['paper', 'ink', 'muted', 'line', 'surface', 'accent', 'danger', 'ok'];
const FONTS = ['Maple Mono', 'Instrument Serif'];
const VOICES = ['plain', 'caps', 'bracket'];
const HEX = /^#[0-9A-Fa-f]{6}$/;
const NIRI_COLORS = ['border_inactive', 'ring_color', 'shadow_color', 'shadow_inactive'];

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
  const primitive = doc.primitive ?? fail('missing [primitive]');
  for (const [k, menu] of Object.entries(MENUS)) {
    if (!menu.includes(primitive[k])) fail(`primitive.${k}: "${primitive[k]}" is not one of ${menu.join(', ')}`);
  }
  const type = doc.type ?? fail('missing [type]');
  for (const k of ['display', 'ui', 'mono']) if (!FONTS.includes(type[k])) fail(`type.${k}: "${type[k]}" is not one of ${FONTS.join(', ')}`);
  if (!VOICES.includes(type.voice)) fail(`type.voice: "${type.voice}" is not one of ${VOICES.join(', ')}`);
  const niri = doc.niri ?? fail('missing [niri]');
  for (const k of NIRI_COLORS) {
    if (k in niri && !/^#[0-9A-Fa-f]{6}([0-9A-Fa-f]{2})?$/.test(niri[k])) fail(`niri.${k}: "${niri[k]}" is not #RRGGBB or #RRGGBBAA`);
  }
  return {
    name: meta.name,
    mode: meta.mode,
    color: Object.assign({}, color, { ansi: [...color.ansi] }),
    primitive: Object.assign({}, primitive),
    paper: Object.assign({}, doc.paper),
    type: { display: type.display, ui: type.ui, mono: type.mono, voice: type.voice, scale: type.scale ?? 1 },
    niri: Object.assign({}, niri, { gaps: niri.gaps ?? 16, border: niri.border ?? 1, blur: niri.blur ?? false }),
  };
}

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

// The shell's tokens come from shell.json, so they get the same check as theme.toml.
export function checkTokens(t) {
  return validateTheme(Object.assign({}, t, { meta: { name: t.name, mode: t.mode } }));
}

const CURVES = {
  spring: 'spring damping-ratio=0.72 stiffness=380 epsilon=0.0001',
  snappy: 'duration-ms 120\n        curve "ease-out-expo"',
  ease: 'duration-ms 200\n        curve "ease-out-cubic"',
  typewriter: 'duration-ms 90\n        curve "linear"',
  linear: 'duration-ms 150\n        curve "linear"',
};

const spring = (d, k) => `spring damping-ratio=${d} stiffness=${k} epsilon=0.0001`;
const eased = (ms, curve) => `duration-ms ${ms}\n        curve "${curve}"`;
// Every animation's timing for the three motions the Motion boards draw (agent #W2A0F2JH); another motion keeps CURVES for open and close only.
const MOTION = {
  snappy: {
    'window-open': eased(140, 'ease-out-expo'),
    'window-close': eased(100, 'ease-out-quad'),
    'workspace-switch': spring('1.0', 1200),
    'horizontal-view-movement': spring('1.0', 1000),
    'window-movement': spring('1.0', 1000),
    'window-resize': spring('1.0', 1000),
    'overview-open-close': eased(160, 'ease-out-expo'),
    'screenshot-ui-open': eased(120, 'ease-out-expo'),
    'config-notification-open-close': spring('1.0', 1000),
    'exit-confirmation-open-close': spring('1.0', 1000),
  },
  spring: {
    'window-open': spring(0.72, 380),
    'window-close': eased(160, 'ease-out-quad'),
    'workspace-switch': spring(0.85, 600),
    'horizontal-view-movement': spring(0.9, 700),
    'window-movement': spring(0.8, 600),
    'window-resize': spring(0.85, 600),
    'overview-open-close': spring(0.85, 600),
    'screenshot-ui-open': eased(200, 'ease-out-cubic'),
    'config-notification-open-close': spring(0.6, 1000),
    'exit-confirmation-open-close': spring(0.6, 1000),
  },
  linear: {
    'window-open': eased(220, 'linear'),
    'window-close': eased(160, 'linear'),
    'workspace-switch': eased(200, 'ease-out-cubic'),
    'horizontal-view-movement': eased(200, 'ease-out-cubic'),
    'window-movement': eased(150, 'linear'),
    'window-resize': eased(150, 'linear'),
    'overview-open-close': eased(180, 'linear'),
    'screenshot-ui-open': eased(150, 'linear'),
    'config-notification-open-close': eased(150, 'linear'),
    'exit-confirmation-open-close': eased(150, 'linear'),
  },
};

// A #RRGGBB colour as an opaque GLSL vec4, so a shader draws in the theme's own ink.
const glslColor = (hex) => `vec4(${[1, 3, 5].map((i) => (parseInt(hex.slice(i, i + 2), 16) / 255).toFixed(3)).join(', ')}, 1.0)`;

// niri draws the whole tile into niri_tex, border, ring and shadow included, so a shader samples it past the geometry and stops only at the texture's edge.
const TEX = `vec4 dots_tex(vec3 coords_geo) {
    vec3 t = niri_geo_to_tex * coords_geo;
    if (t.x < 0.0 || t.x > 1.0 || t.y < 0.0 || t.y > 1.0) return vec4(0.0);
    return texture2D(niri_tex, t.st);
}`;

// How far along the 1 px outline, clockwise from the top-left corner, a pixel lies; -1.0 off the outline.
const OUTLINE = `float dots_outline(vec2 px, vec2 size) {
    if (px.x < 0.0 || px.y < 0.0 || px.x >= size.x || px.y >= size.y) return -1.0;
    if (px.y < 1.0) return px.x;
    if (px.x >= size.x - 1.0) return size.x + px.y;
    if (px.y >= size.y - 1.0) return 2.0 * size.x + size.y - px.x;
    if (px.x < 1.0) return 2.0 * (size.x + size.y) - px.y;
    return -1.0;
}`;

// The open and close shaders the Motion boards draw, by motion; the Blueprint pen is the accent.
const SHADERS = {
  snappy: () => ({
    // Whole from the first frame, 8 px above its place, dropping into it.
    open: `${TEX}
vec4 open_color(vec3 coords_geo, vec3 size_geo) {
    float p = niri_clamped_progress;
    return dots_tex(vec3(coords_geo.x, coords_geo.y + 8.0 * (1.0 - p) / size_geo.y, 1.0));
}`,
    // Lifts 8 px while a cut climbs from just below its shadow to its top.
    close: `${TEX}
vec4 close_color(vec3 coords_geo, vec3 size_geo) {
    float p = niri_clamped_progress;
    vec3 c = vec3(coords_geo.x, coords_geo.y + 8.0 * p / size_geo.y, 1.0);
    if (c.y > (1.0 - p) * (1.0 + 8.0 / size_geo.y)) return vec4(0.0);
    return dots_tex(c);
}`,
  }),
  linear: (c) => {
    const pen = glslColor(c.accent);
    return {
      // The outline is traced until 55%; from 45% a scan line comes down and shows the window above it.
      open: `${TEX}
${OUTLINE}
vec4 open_color(vec3 coords_geo, vec3 size_geo) {
    float p = niri_clamped_progress;
    vec2 px = coords_geo.xy * size_geo.xy;
    float scan = (p - 0.45) / 0.55 * size_geo.y;
    vec4 color = px.y < scan ? dots_tex(coords_geo) : vec4(0.0);
    float d = dots_outline(px, size_geo.xy);
    bool inside = px.x >= 0.0 && px.x < size_geo.x && px.y >= 0.0 && px.y < size_geo.y;
    if (inside && p < 1.0 && px.y >= scan && px.y < scan + 1.0) color = ${pen};
    if (d >= 0.0 && d <= min(p / 0.55, 1.0) * 2.0 * (size_geo.x + size_geo.y)) color = ${pen};
    return color;
}`,
      // A scan line goes up and takes the window with it in the first 60%; then the outline is lifted, last drawn first.
      close: `${TEX}
${OUTLINE}
vec4 close_color(vec3 coords_geo, vec3 size_geo) {
    float p = niri_clamped_progress;
    vec2 px = coords_geo.xy * size_geo.xy;
    float scan = (1.0 - p / 0.6) * size_geo.y;
    vec4 color = px.y < scan ? dots_tex(coords_geo) : vec4(0.0);
    float d = dots_outline(px, size_geo.xy);
    bool inside = px.x >= 0.0 && px.x < size_geo.x && px.y >= 0.0 && px.y < size_geo.y;
    if (inside && p < 0.6 && px.y >= scan && px.y < scan + 1.0) color = ${pen};
    if (d >= 0.0 && d <= clamp((1.0 - p) / 0.4, 0.0, 1.0) * 2.0 * (size_geo.x + size_geo.y)) color = ${pen};
    return color;
}`,
    };
  },
};

const indent = (text, pad) => text.split('\n').map((l) => (l ? pad + l : l)).join('\n');

export function renderNiri(t) {
  const c = t.color;
  const n = t.niri;
  const frameColor = t.primitive.frame === 'glow' ? c.accent : c.ink;
  const border = t.primitive.frame === 'none' || !n.border
    ? 'border {\n        off\n    }'
    : `border {\n        on\n        width ${n.border}\n        active-color "${frameColor}"\n        inactive-color "${n.border_inactive ?? c.muted}"\n    }`;
  const ring = n.ring_width
    ? `focus-ring {\n        on\n        width ${n.ring_width}\n        active-color "${n.ring_color ?? c.accent}"\n    }`
    : 'focus-ring {\n        off\n    }';
  // The glow of a glow frame is niri's shadow, so the shadow follows the [niri] keys, not the shadow primitive.
  const [ox, oy] = n.shadow_offset ?? [0, 0];
  const shadow = n.shadow_color
    ? [
      'shadow {', '        on', `        softness ${n.shadow_softness ?? 30}`, `        spread ${n.shadow_spread ?? 0}`,
      `        offset x=${ox} y=${oy}`, `        color "${n.shadow_color}"`,
      ...(n.shadow_inactive ? [`        inactive-color "${n.shadow_inactive}"`] : []), '    }',
    ].join('\n')
    : 'shadow {\n        off\n    }';
  const radius = t.primitive.corner === 'round' ? 14 : 0;
  const motion = MOTION[t.primitive.motion]
    ?? { 'window-open': CURVES[t.primitive.motion], 'window-close': CURVES[t.primitive.motion] };
  const shaders = SHADERS[t.primitive.motion]?.(c) ?? {};
  const shader = (name) => {
    const glsl = shaders[{ 'window-open': 'open', 'window-close': 'close' }[name]];
    return glsl ? `\n        custom-shader r"\n${indent(glsl, '            ')}\n        "` : '';
  };
  const animations = Object.entries(motion).map(([name, timing]) => `    ${name} {\n        ${timing}${shader(name)}\n    }`).join('\n');
  return `layout {
    gaps ${t.niri.gaps}
    background-color "${c.paper}"
    ${ring}
    ${border}
    ${shadow}
    // Windows start 56 px down and 32 px in, below the margins, as on the approved artboard.
    struts {
        top ${56 - t.niri.gaps}
        bottom ${28 - t.niri.gaps}
        left ${32 - t.niri.gaps}
        right ${32 - t.niri.gaps}
    }
}

prefer-no-csd

window-rule {
    geometry-corner-radius ${radius}
    clip-to-geometry true
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
  const entries = [['main', 'initial-color-theme', t.mode], [s, 'background', hex(c.surface)], [s, 'foreground', hex(c.ink)]];
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
