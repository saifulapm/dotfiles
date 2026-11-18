// The notification centre as board 5 draws it inside the island: pure pieces, so node can test them.
import { group, ruleOf, visible } from './notifs.mjs';
import { line } from './voice.mjs';

const stayText = (ms) => (ms === 0 ? 'Until dismissed' : ms / 1000 + ' s');

// A group's badge: Muted, or Through DND, then how long it stays; an app with no rule has none.
export function badgeText(rule) {
  if (!rule) return '';
  const parts = [];
  if (rule.muted) parts.push('Muted');
  else if (rule.dnd) parts.push('Through DND');
  if (rule.stays >= 0) parts.push(stayText(rule.stays));
  return parts.join(' · ');
}

// The rules tile's three rows, in the order board 5 draws them.
export const RULES = ['muted', 'dnd', 'stays'];

// One row per thing the list draws, in order: each app's head, its rules tile's rows while open, then its notes.
export function centreRows(history, query, rules, openRules) {
  const rows = [];
  group(visible(history, query)).forEach((g, i) => {
    const rule = ruleOf(rules, g.app);
    const name = line(g.app);
    rows.push({ kind: 'head', app: g.app, name, letter: name.charAt(0).toUpperCase() || '•', badge: badgeText(rule), first: i === 0 });
    if (g.app === openRules) for (const field of RULES) rows.push({ kind: 'rule', app: g.app, field, greyed: field === 'dnd' && !!rule?.muted });
    for (const entry of g.entries) rows.push({ kind: 'note', app: g.app, entry });
  });
  return rows;
}

// The header's count: every notification, or how many a search leaves of them.
export const countText = (shown, total, query) => (total === 0 ? '' : query ? `${shown} of ${total}` : String(total));

// The row the centre opens on: the newest note, past its app's head.
export function firstNote(rows) {
  const i = rows.findIndex((r) => r.kind === 'note');
  return i < 0 ? 0 : i;
}

// An age in whole units, floored, as board 5 writes it.
export function ageText(ms) {
  const s = Math.floor(ms / 1000);
  return s < 60 ? 'now' : s < 3600 ? `${Math.floor(s / 60)} min` : s < 86400 ? `${Math.floor(s / 3600)} h` : `${Math.floor(s / 86400)} d`;
}
