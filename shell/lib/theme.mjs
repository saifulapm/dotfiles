// Validates a parsed theme.toml and renders its fragments; pure, so the shell can import it too.
const MENUS = {
  paper: ['flat', 'grain', 'dots', 'grid', 'gradient'],
  frame: ['hairline', 'ink', 'double', 'none', 'glow'],
  shadow: ['soft', 'hard-offset', 'none'],
  corner: ['round', 'square', 'cut'],
  motion: ['spring', 'snappy', 'ease', 'typewriter', 'linear'],
};
const COLORS = ['paper', 'ink', 'muted', 'line', 'surface', 'accent', 'danger', 'ok'];
const FONTS = ['Maple Mono', 'Inter', 'Instrument Serif'];
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
    type: { display: type.display, ui: type.ui, mono: type.mono, scale: type.scale ?? 1 },
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
  const curve = CURVES[t.primitive.motion];
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
    window-open {
        ${curve}
    }
    window-close {
        ${curve}
    }
}
`;
}

export function renderFoot(t) {
  const hex = (s) => s.slice(1).toUpperCase();
  const c = t.color;
  const lines = ['[colors]', `background=${hex(c.surface)}`, `foreground=${hex(c.ink)}`];
  c.ansi.forEach((v, i) => lines.push(`${i < 8 ? 'regular' : 'bright'}${i % 8}=${hex(v)}`));
  return lines.join('\n') + '\n';
}
