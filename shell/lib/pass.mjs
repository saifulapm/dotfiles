// Pass's rows from `dots-pass list` ("name\totp" per line, recent first); no secret ever comes through here.
import { inOrder, line } from './voice.mjs';

export function parseEntries(text) {
  return String(text)
    .split('\n')
    .filter((l) => l.includes('\t'))
    .map((l) => {
      const name = l.slice(0, l.lastIndexOf('\t'));
      const cut = name.lastIndexOf('/') + 1;
      return { name, folder: name.slice(0, cut), leaf: name.slice(cut), otp: l.slice(l.lastIndexOf('\t') + 1) === '1' };
    });
}

// The positions of the query's letters in the name, leftmost first, or null when they are not all there in order.
function hits(name, needle) {
  const out = [];
  let from = 0;
  for (const ch of needle) {
    const at = name.indexOf(ch, from);
    if (at < 0) return null;
    out.push(at);
    from = at + 1;
  }
  return out;
}

// A store holds tens of entries, so the filter keeps the recent-first order instead of scoring.
export function passRows(entries, q) {
  const needle = q.trim().toLowerCase();
  return entries
    .map((e) => Object.assign({ hits: hits(e.name.toLowerCase(), needle) }, e))
    .filter((r) => r.hits !== null);
}

// Runs of the name with the same look: the folder muted, matched letters underlined; bidi controls are dropped, so a name draws in the order it is spelt.
export function segments(row) {
  const marked = new Set(row.hits);
  const runs = [];
  for (let i = 0; i < row.name.length; i++) {
    const ch = inOrder(row.name[i]);
    if (!ch) continue;
    const look = { folder: i < row.folder.length, hit: marked.has(i) };
    const last = runs[runs.length - 1];
    if (last && last.folder === look.folder && last.hit === look.hit) last.text += ch;
    else runs.push({ text: ch, folder: look.folder, hit: look.hit });
  }
  return runs;
}

export function passKeys(look) {
  return look.keys([['↵', 'copy'], ['o', 'otp'], ['s', 'show'], ['n', 'new'], ['e', 'edit'], ['d', 'delete'], ['q', 'qr'], ['esc', '']]);
}

export const copiedText = (kind) => (kind === 'otp' ? 'OTP copied' : 'Copied') + ' · clears in 45s';

export function failedText(stderr) {
  const why = line(String(stderr).split('\n')[0].replace(/^dots-pass: /, ''));
  return why ? `Not copied · ${why}` : 'Not copied';
}
