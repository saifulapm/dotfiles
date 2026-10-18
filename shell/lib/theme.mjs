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
  return {
    name: meta.name,
    mode: meta.mode,
    color: { ...color, ansi: [...color.ansi] },
    primitive: { ...primitive },
    paper: { ...(doc.paper ?? {}) },
    type: { display: type.display, ui: type.ui, mono: type.mono, scale: type.scale ?? 1 },
    niri: { gaps: niri.gaps ?? 16, border: niri.border ?? 1, blur: niri.blur ?? false },
  };
}

const CURVES = {
  spring: 'spring damping-ratio=0.8 stiffness=600 epsilon=0.0001',
  snappy: 'duration-ms 120\n        curve "ease-out-expo"',
  ease: 'duration-ms 200\n        curve "ease-out-cubic"',
  typewriter: 'duration-ms 90\n        curve "linear"',
  linear: 'duration-ms 150\n        curve "linear"',
};

export function renderNiri(t) {
  const c = t.color;
  const frameColor = t.primitive.frame === 'glow' ? c.accent : c.ink;
  const border = t.primitive.frame === 'none'
    ? 'border {\n        off\n    }'
    : `border {\n        width ${t.niri.border}\n        active-color "${frameColor}"\n        inactive-color "${c.muted}"\n    }`;
  const shadow = {
    soft: `shadow {\n        on\n        softness 30\n        spread 2\n    }`,
    'hard-offset': `shadow {\n        on\n        softness 0\n        spread 0\n        offset x=2 y=2\n        color "${c.ink}"\n        inactive-color "${c.muted}"\n    }`,
    none: 'shadow {\n        off\n    }',
  }[t.primitive.shadow];
  const radius = t.primitive.corner === 'round' ? 14 : 0;
  const curve = CURVES[t.primitive.motion];
  return `layout {
    gaps ${t.niri.gaps}
    background-color "${c.paper}"
    focus-ring {
        off
    }
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
