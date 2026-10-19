// How the launcher draws under a token set, from its voice, as the three Launcher boards do.

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
