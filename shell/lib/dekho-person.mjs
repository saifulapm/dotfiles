// The Person page's words and choices: life years, credits split by role, and the board's wording.
import { stars } from './dekho.mjs';
import { oneLine } from './picker.mjs';

const cap = (s) => s.charAt(0).toUpperCase() + s.slice(1);

// The backend's group order, which is also the board's.
const ORDER = ['directing', 'acting', 'writing'];

// A birthday opens the years, a deathday closes them; without a birthday there is nothing to say.
export function years(birthday, deathday) {
  if (!birthday) return '';
  return deathday ? `${birthday.slice(0, 4)} – ${deathday.slice(0, 4)}` : `${birthday.slice(0, 4)} –`;
}

// An actor played a part; anyone else held a job.
const roleLine = (key, role) => {
  const r = oneLine(role);
  return key === 'acting' && r ? `as ${r}` : r;
};

// The credits by role, a role with none left out.
export function groups(credits) {
  return ORDER.map((key) => ({ key, rows: ((credits || {})[key] || []).map((h) => Object.assign({}, h, { titleText: oneLine(h.title), roleText: roleLine(key, h.role), voteText: stars(h.vote) })) }))
    .filter((g) => g.rows.length)
    .map((g) => Object.assign(g, { count: g.rows.length }));
}

// Headings and credits as one list, each credit numbered through the whole page so a cursor can walk it.
export function lines(gs) {
  const out = [];
  let index = 0;
  gs.forEach((g) => {
    out.push({ head: true, key: g.key, count: g.count });
    g.rows.forEach((row) => out.push({ head: false, key: g.key, index: index++, row }));
  });
  return out;
}

export const kindText = (kind) => (kind === 'tv' ? 'series' : 'film');

export function subline(birthday, deathday, gs) {
  return [years(birthday, deathday)].concat(gs.map((g) => cap(g.key))).filter((p) => p).join(' · ');
}

export function initials(name) {
  const words = oneLine(name).split(' ').filter((w) => w);
  return words.length ? (words[0][0] + (words.length > 1 ? words[words.length - 1][0] : '')).toUpperCase() : '';
}

export const firstName = (name) => oneLine(name).split(' ')[0];

// The words the board writes on the Person page.
export function personText() {
  return {
    label: 'Dekho',
    page: 'person',
    heading: (key) => cap(key),
    filmography: (n) => `Filmography · ${n} ${n === 1 ? 'credit' : 'credits'}`,
    next: 'tab next role',
    keys: (gs, name) => [['j/k', 'move'], ['↵', 'open title'], ['tab', `next role: ${gs.map((g) => g.key).join(', ')}`], ['f', `filter the library by ${firstName(name)}`], ['/', 'search'], ['esc', 'back']],
  };
}
