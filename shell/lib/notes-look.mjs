// How the Notes window draws under a token set, from its primitives and type, as the three Notes designs do.

import { SHELF, displayText } from './notes.mjs';

const TAG_ANSI = { red: 1, orange: 3, yellow: 11, green: 2, blue: 4, purple: 5 };

export const tagColour = (tokens, tag) => tokens.color.ansi[TAG_ANSI[tag]];

// What the key strip lists, and the one line an empty Notes shows.
export const KEYS = [['j/k', ''], ['␣', 'done'], ['↵', 'edit'], ['1–6', 'tag'], ['v', 'select'], ['m', 'merge'], ['⇧M', 'move'], ['y', 'text'], ['⇧Y', 'image'], ['⌃Y', 'list'], ['⌃V', 'attach'], ['d', 'delete'], ['/', 'search'], ['⌃K', 'sections'], ['esc', 'back']];
export const EMPTY_KEYS = [['↵', 'save'], ['# name', 'section'], ['⌃V', 'attach']];
export const COMPOSER_KEYS = [['↵', 'save'], ['⇧↵', 'line'], ['# name', 'section'], ['⌃V', 'attach']];

// What Shelf's composer says in place of the add-a-note prompt, as its design words it.
export const SHELF_PLACEHOLDER = '⌃V paste · drop files or images here · ↵ save text';

// A section name is typed text that syncs in: one line, bidi marks shown, before it is drawn.
const oneLine = (name) => displayText(name).replace(/[\u0000-\u001f\u007f-\u009f]+/g, ' ').trim();

// The tab row: the sections in the picker's order, Shelf pinned (drawn with a pin, not a #), the current one marked.
export function tabLabels(look, names, current) {
  return names.map((name) => {
    const shown = oneLine(name);
    const pinned = name === SHELF;
    return { name, label: pinned ? shown : look.sectionLabel(shown), pinned, current: name === current };
  });
}

// "13:55 · text", "15:08 · image", or the file's type: the small line under a Shelf card.
export function cardMeta(note) {
  const d = new Date(note.createdAt);
  const time = String(d.getHours()).padStart(2, '0') + ':' + String(d.getMinutes()).padStart(2, '0');
  const first = note.attachments[0];
  const ext = first ? (first.name.match(/\.([A-Za-z0-9]+)$/) ?? [])[1] : '';
  const kind = !first ? 'text' : note.attachments.some((a) => a.mime.indexOf('image/') === 0) ? 'image' : ext ? ext.toUpperCase() : 'file';
  return `${time} · ${kind}`;
}

export const keyPairs = (keys) => keys.map(([k, what]) => (what ? `${k} ${what}` : k));

export const keyLine = (keys) => keyPairs(keys).join('  ');

// Two hex colours mixed, a share of the second into the first.
export function mix(a, b, share) {
  const ch = (h, i) => parseInt(h.slice(1 + 2 * i, 3 + 2 * i), 16);
  const out = [0, 1, 2].map((i) => Math.round(ch(a, i) * (1 - share) + ch(b, i) * share).toString(16).padStart(2, '0'));
  return '#' + out.join('');
}

// Notes on the one design: square, a 1 px ink frame, the plain voice.
export function notesLook(tokens) {
  const c = tokens.color;
  const t = tokens.type;
  return {
    keyHint: '⌃K',
    title: { text: 'Notes', font: t.ui, size: 17, bold: true, color: c.ink, spacing: 0 },
    sectionLabel: (name) => `# ${name}`,
    section: { font: t.ui, size: 12, italic: false, color: c.ink, pill: 'transparent' },
    pinned: { text: 'Pinned', color: c.accent, fill: 'transparent', border: 1 },
    separator: '',
    small: { font: t.mono, size: 11, color: c.muted, spacing: 0 },
    body: { font: t.ui, size: 14, color: c.ink, done: c.muted },
    composer: { font: t.ui, size: 14, italic: false, prompt: '', placeholder: 'Add a note or a prompt…', fill: 'transparent', radius: 0 },
    radius: 0,
    // The selected card is outlined 2 px in the accent; the rest in ink, or the line colour once done.
    card(selected, done) {
      return { fill: c.surface, border: { width: selected ? 2 : 1, color: selected ? c.accent : done ? c.line : c.ink } };
    },
  };
}
