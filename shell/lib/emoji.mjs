// Emoji for the launcher: the parser behind bin/dots-emoji-data and the rows shell/data/emoji.json becomes.
import { rank } from './launcher.mjs';

const LINE = /;\s*fully-qualified\s*#\s*(\S+)\s+E\d+\.\d+\s+(.+)$/;

// Keeps fully-qualified entries and drops the skin-tone variants, so each person or hand appears once.
export function parseEmojiTest(text) {
  const out = [];
  let group = '';
  text.split('\n').forEach((line) => {
    if (line.startsWith('# group: ')) group = line.slice(9).trim();
    const m = LINE.exec(line);
    if (m && !m[2].includes('skin tone')) out.push([m[1], m[2], group]);
  });
  return out;
}

// The emoji is argv, never shell text; the sleep lets niri hand the keyboard back to the window before wtype.
const TYPE = 'printf %s "$1" | wl-copy; sleep 0.1; wtype -- "$1"';

// Entries are [emoji, name, group]; the group matches as a keyword.
export function emojiRows(list, q) {
  return rank(
    list.map((e) => ({ name: e[1], keywords: [e[2]], e })),
    q,
  ).map((x) => ({ title: x.e[0] + ' ' + x.e[1], bare: x.e[1], glyph: x.e[0], detail: x.e[2], exec: ['sh', '-c', TYPE, 'sh', x.e[0]] }));
}
