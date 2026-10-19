// How the shell speaks under a token set, from its voice, as the three themes' boards draw it: the launcher, the island's notification and OSD.

export const MODES = ['apps', 'windows', 'clipboard', 'emoji', 'calculator', 'commands'];

// Each mode's prefix and the word the boards give it; Artboard spells calculator out.
const PREFIXES = [['w', 'windows'], ['v', 'clipboard'], [':', 'emoji'], ['=', 'calc'], ['>', 'commands']];
const PLAIN_WORD = { calc: 'calculator' };
const CAPS_NAME = { calculator: 'CALC' };

// Artboard's board tints, which no token carries and no mix of tokens lands on.
const ARTBOARD = { tint: '#EEF1FF', deep: '#2638C9', tile: '#F2F3F6' };

// An open can come before the theme's tokens load; until then the launcher draws in black and white.
const UNTHEMED = { color: { ink: 'white', muted: 'gray', line: 'gray', surface: 'black', accent: 'white' }, type: { display: '', ui: '', mono: '', voice: 'caps' } };

// Bidi embedding, override and isolate controls, which let an app's name redraw itself in another order.
const BIDI = /[\u202A-\u202E\u2066-\u2069]/g;
const same = (s) => (s || '').replace(BIDI, '');
const upper = (s) => same(s).toUpperCase();

export function launcherLook(tokens) {
  const c = (tokens || UNTHEMED).color;
  const t = (tokens || UNTHEMED).type;
  const voice = t.voice;
  const caps = voice !== 'plain';
  const key = (k) => (voice === 'bracket' ? `[${upper(k)}]` : caps ? upper(k) : k);
  const legend = (mode) => ({
    keys: mode === 'apps' ? PREFIXES.map(([k, w]) => ({ key: key(k), word: caps ? upper(w) : PLAIN_WORD[w] || w })) : [],
    tail: caps ? 'J/K · ↵ · ESC' : 'j/k · ↵ · esc',
    chips: voice === 'plain',
  });
  const base = {
    voice,
    legend,
    legendLine(mode) {
      const l = legend(mode);
      return l.keys.map((k) => `${k.key} ${k.word}`).concat([l.tail]).join('  ');
    },
    number: (i) => String(i + 1).padStart(2, '0'),
    title: same,
    detailText: same,
    count: () => '',
    prompt: { text: '', color: c.accent, search: false },
    caret: 'line',
    rule: { color: c.ink, dashed: false },
    small: { font: t.ui, size: 10, spacing: 1.4, color: c.muted },
    tile: { size: 32, radius: 9, fill: ARTBOARD.tile },
  };
  if (voice === 'plain') {
    return Object.assign(base, {
      query: { font: t.ui, size: 20, italic: false },
      prompt: { text: '', color: c.muted, search: true },
      label: { kind: 'pill', text: (m) => m.charAt(0).toUpperCase() + m.slice(1), fill: ARTBOARD.tint, color: c.accent },
      slot: 'icon',
      name: { font: t.ui, size: 15, weight: 500, spacing: 0, color: c.ink },
      detail: { font: t.ui, size: 12, italic: false, color: c.muted },
      cursor: { fill: ARTBOARD.tint, text: ARTBOARD.deep, detail: c.muted, marker: 'transparent', radius: 10, weight: 600, badge: '↵' },
      rule: { color: c.line, dashed: false },
      small: { font: t.ui, size: 11, spacing: 0, color: c.muted },
      chip: { fill: ARTBOARD.tile, key: c.ink },
    });
  }
  if (voice === 'bracket') {
    return Object.assign(base, {
      query: { font: t.mono, size: 22, italic: false },
      prompt: { text: '>', color: c.accent, search: false },
      caret: 'block',
      label: { kind: 'header', text: (m) => `LAUNCH // ${upper(m)}`, fill: 'transparent', color: c.muted },
      count: (n) => `${n} MATCHES`,
      slot: 'number',
      title: upper,
      detailText: upper,
      name: { font: t.mono, size: 15, weight: 400, spacing: 0.6, color: c.ink },
      detail: { font: t.mono, size: 11, italic: false, spacing: 1.3, color: c.muted },
      cursor: { fill: c.accent, text: c.surface, detail: c.surface, marker: 'transparent', radius: 0, weight: 700, badge: '' },
      rule: { color: c.line, dashed: true },
      small: { font: t.mono, size: 10, spacing: 1.6, color: c.muted },
      chip: { fill: 'transparent', key: c.accent },
    });
  }
  return Object.assign(base, {
    query: { font: t.display, size: 34, italic: false },
    label: { kind: 'chip', text: (m) => CAPS_NAME[m] || upper(m), fill: c.ink, color: c.surface },
    count: (n) => `${n} FOUND`,
    slot: 'marker',
    name: { font: t.ui, size: 15, weight: 400, spacing: 0, color: c.ink },
    detail: { font: t.display, size: 16, italic: true, color: c.muted },
    cursor: { fill: c.ink, text: c.surface, detail: c.line, marker: c.accent, radius: 0, weight: 500, badge: '' },
    chip: { fill: 'transparent', key: c.ink },
  });
}

// The island's board tints on its dark box, which no token carries.
const ISLAND = {
  caps: { head: '#B9AE99', body: '#D9CFBB' },
  plain: { head: '#A3A9B4', body: '#C9CED6', summary: '#FFFFFF', tile: '#2B2F36', bar: '#6C83FF' },
};

// How the island draws a notification; every colour not named here is the island's own text colour.
export function islandLook(tokens) {
  const c = (tokens || UNTHEMED).color;
  const t = (tokens || UNTHEMED).type;
  const voice = t.voice;
  const appText = (app) => (voice === 'plain' ? same(app) : upper(app));
  const base = {
    voice,
    appText,
    brackets: voice === 'bracket',
    appLabel(app) {
      const a = appText(app);
      return a && voice === 'bracket' ? `[ ${a} ]` : a;
    },
    summaryText: same,
    glyph: (app) => upper(app).charAt(0) || '•',
    tile: null,
  };
  if (voice === 'plain') {
    return Object.assign(base, {
      width: 440,
      age: 'now',
      pad: { x: 16, top: 14, bottom: 14 },
      head: { font: t.ui, size: 12, spacing: 0, color: ISLAND.plain.head },
      summary: { font: t.ui, size: 15, weight: 600, spacing: 0, color: ISLAND.plain.summary },
      body: { font: t.ui, size: 13, color: ISLAND.plain.body },
      tile: { size: 40, radius: 12, fill: ISLAND.plain.tile },
    });
  }
  if (voice === 'bracket') {
    return Object.assign(base, {
      width: 420,
      age: 'T+0S',
      pad: { x: 18, top: 12, bottom: 14 },
      head: { font: t.mono, size: 10, spacing: 1.6, color: c.muted },
      summary: { font: t.mono, size: 15, weight: 700, spacing: 0.6, color: c.accent },
      summaryText: upper,
      body: { font: t.mono, size: 12, color: c.ink },
    });
  }
  return Object.assign(base, {
    width: 420,
    age: 'NOW',
    pad: { x: 16, top: 12, bottom: 14 },
    head: { font: t.ui, size: 10, spacing: 1.4, color: tokens ? ISLAND.caps.head : c.muted },
    summary: { font: t.display, size: 24, weight: 400, spacing: 0, color: '' },
    body: { font: t.mono, size: 12, color: tokens ? ISLAND.caps.body : c.ink },
  });
}

// How the island draws the volume or brightness OSD: 20 bars, Blueprint's blocks or Artboard's one rounded bar.
export function osdLook(tokens) {
  const c = (tokens || UNTHEMED).color;
  const t = (tokens || UNTHEMED).type;
  const voice = t.voice;
  const base = {
    voice,
    litCount: (v) => Math.round(Math.max(0, Math.min(100, v)) / 5),
    word: (kind) => (kind === 'brightness' ? 'BRT' : 'VOL'),
    valueText: (v) => String(v),
  };
  if (voice === 'plain') {
    return Object.assign(base, {
      width: 300,
      height: 40,
      word: () => '',
      bars: 'round',
      lit: { color: tokens ? ISLAND.plain.bar : c.accent },
      unlit: { color: tokens ? ISLAND.plain.tile : c.muted },
      value: { font: t.ui, size: 13, weight: 600, color: '' },
    });
  }
  if (voice === 'bracket') {
    return Object.assign(base, {
      width: 320,
      height: 34,
      bars: 'blocks',
      lit: { color: c.accent },
      unlit: { color: c.line },
      valueText: (v) => String(v).padStart(3, '0'),
      value: { font: t.mono, size: 12, weight: 700, color: c.accent },
      label: { font: t.mono, size: 12, spacing: 1.7, color: c.muted },
    });
  }
  return Object.assign(base, {
    width: 280,
    height: 34,
    bars: 'bars',
    lit: { color: c.accent },
    unlit: { color: c.muted },
    value: { font: t.display, size: 18, weight: 400, color: '' },
    label: { font: t.ui, size: 10, spacing: 1.4, color: '' },
  });
}
