// How the Notes window draws under a token set, from its primitives and type, as the three Notes designs do.

const TAG_ANSI = { red: 1, orange: 3, yellow: 11, green: 2, blue: 4, purple: 5 };

export const tagColour = (tokens, tag) => tokens.color.ansi[TAG_ANSI[tag]];

// What the key strip lists, and the one line an empty Notes shows.
export const KEYS = [['j/k', ''], ['␣', 'done'], ['↵', 'edit'], ['1–6', 'tag'], ['v', 'select'], ['m', 'merge'], ['⇧M', 'move'], ['y', 'text'], ['⇧Y', 'image'], ['⌃Y', 'list'], ['⌃V', 'attach'], ['d', 'delete'], ['/', 'search'], ['⌃K', 'sections'], ['esc', 'back']];
export const EMPTY_KEYS = [['↵', 'save'], ['# name', 'section'], ['⌃V', 'attach']];
export const COMPOSER_KEYS = [['↵', 'save'], ['⇧↵', 'line'], ['# name', 'section'], ['⌃V', 'attach']];

// Blueprint's display face is its mono, Paper's is a serif beside a mono UI, Artboard's is its UI face.
function voiceOf(t) {
  if (t.display === t.mono) return 'bracket';
  return t.ui === t.mono ? 'caps' : 'plain';
}

export function keyPairs(tokens, keys) {
  const voice = voiceOf(tokens.type);
  return keys.map(([k, what]) => {
    const key = voice === 'bracket' ? `[${k.toUpperCase()}]` : voice === 'caps' ? k.toUpperCase() : k;
    const word = voice === 'plain' ? what : what.toUpperCase();
    return word ? `${key} ${word}` : key;
  });
}

export const keyLine = (tokens, keys) => keyPairs(tokens, keys).join('  ');

// Two hex colours mixed, a share of the second into the first.
function mix(a, b, share) {
  const ch = (h, i) => parseInt(h.slice(1 + 2 * i, 3 + 2 * i), 16);
  const out = [0, 1, 2].map((i) => Math.round(ch(a, i) * (1 - share) + ch(b, i) * share).toString(16).padStart(2, '0'));
  return '#' + out.join('');
}

export function notesLook(tokens) {
  const c = tokens.color;
  const t = tokens.type;
  const p = tokens.primitive;
  const voice = voiceOf(t);
  const round = p.corner === 'round';
  const tint = mix(c.surface, c.paper, 0.3);
  return {
    voice,
    title:
      voice === 'bracket'
        ? { text: 'NOTES', font: t.mono, size: 11, bold: true, color: c.accent, spacing: 1.5 }
        : voice === 'caps'
          ? { text: 'Notes', font: t.display, size: 30, bold: false, color: c.ink, spacing: 0 }
          : { text: 'Notes', font: t.ui, size: 17, bold: true, color: c.ink, spacing: 0 },
    sectionLabel: (name) => (voice === 'bracket' ? `§${name.toUpperCase()}` : voice === 'caps' ? `§ ${name}` : `# ${name}`),
    section: { font: voice === 'caps' ? t.display : t.ui, size: voice === 'caps' ? 20 : voice === 'bracket' ? 11 : 12, italic: voice === 'caps', color: voice === 'caps' ? c.muted : c.ink, pill: round ? mix(c.surface, c.paper, 0.45) : 'transparent' },
    pinned: { text: voice === 'plain' ? 'Pinned' : 'PINNED', color: voice === 'bracket' ? c.danger : c.accent, fill: round ? mix(c.surface, c.accent, 0.1) : 'transparent', border: round ? 0 : 1 },
    rule: { color: voice === 'bracket' ? c.line : c.ink, width: p.frame === 'none' ? 0 : 1, dashed: voice === 'bracket' },
    strip: { color: voice === 'caps' ? c.ink : c.line, width: 1 },
    separator: voice === 'bracket' ? '//' : '',
    small: { font: t.mono, size: voice === 'plain' ? 11 : 10, color: c.muted, spacing: voice === 'plain' ? 0 : 1.2 },
    body: { font: voice === 'plain' ? t.ui : t.mono, size: voice === 'plain' ? 14 : 13, color: c.ink, done: c.muted },
    composer: { font: voice === 'caps' ? t.display : voice === 'plain' ? t.ui : t.mono, size: voice === 'caps' ? 20 : 14, italic: voice === 'caps', prompt: voice === 'bracket' ? '>' : '', placeholder: voice === 'bracket' ? 'add a note or a prompt' : 'Add a note or a prompt…', fill: round ? tint : 'transparent', radius: round ? 12 : 0 },
    checkbox: voice === 'bracket' ? 'brackets' : 'circle',
    radius: round ? 12 : 0,
    // The selected card is outlined in the accent in every theme; the rest follow the frame primitive.
    card(selected, done) {
      const width = selected ? (p.frame === 'glow' ? 1 : 2) : p.frame === 'none' ? 0 : 1;
      const color = selected ? c.accent : done ? c.line : p.frame === 'glow' ? c.line : c.ink;
      return {
        // Opaque, so a hard shadow drawn behind shows only at its offset.
        fill: round && !selected ? tint : c.surface,
        border: { width, color },
        shadow: selected && p.shadow === 'hard-offset' ? { x: 4, y: 4, color: c.accent } : null,
        dashed: !selected && done && voice === 'bracket',
        glow: selected && p.frame === 'glow',
        ticks: selected && p.corner === 'cut',
      };
    },
  };
}
