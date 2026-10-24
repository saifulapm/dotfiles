// Browse's filters: what each key chooses, the chips they draw, and the dekho api discover calls they make.
import { oneLine } from './picker.mjs';

export const KINDS = ['all', 'movie', 'tv'];
export const SORTS = ['popular', 'top-rated', 'newest', 'oldest', 'box-office'];
export const DECADES = [1970, 1980, 1990, 2000, 2010, 2020];
export const RATINGS = [6, 7, 8];

const KIND_NAMES = { all: 'All', movie: 'Movies', tv: 'Series' };
const SORT_NAMES = { popular: 'Popular', 'top-rated': 'Top rated', newest: 'Newest', oldest: 'Oldest', 'box-office': 'Box office' };

export const kindName = (kind) => KIND_NAMES[kind];
export const sortName = (sort) => SORT_NAMES[sort];

export function empty() {
  return { kind: 'all', sort: 'popular', genre: null, language: null, decade: null, rating: null, person: null };
}

export const clear = () => empty();

export const years = (decade) => `${decade}-${decade + 9}`;

const kindsOf = (kind) => (kind === 'all' ? ['movie', 'tv'] : [kind]);

// TMDB's genres differ by kind, so all offers every name either kind has.
export function genreNames(kind, genres) {
  const names = [];
  kindsOf(kind).forEach((k) => (genres[k] || []).forEach((g) => names.includes(g.name) || names.push(g.name)));
  return names;
}

// The value after this one in the list, and after the last, none.
const after = (list, value) => {
  const at = list.indexOf(value);
  return at + 1 < list.length ? list[at + 1] : null;
};

// One key press on a facet: its next value, wrapping to none (kind to all, sort to popular).
export function next(f, facet, tables) {
  const g = Object.assign({}, f);
  if (facet === 'kind') {
    g.kind = after(KINDS, f.kind) ?? 'all';
    // Series have no box office, and a genre only the other kind has goes with it.
    if (g.kind === 'tv' && g.sort === 'box-office') g.sort = 'popular';
    if (g.genre && !genreNames(g.kind, tables.genres).includes(g.genre)) g.genre = null;
  } else if (facet === 'sort') {
    const sorts = f.kind === 'tv' ? SORTS.filter((s) => s !== 'box-office') : SORTS;
    g.sort = after(sorts, f.sort) ?? 'popular';
  } else if (facet === 'genre') g.genre = after(genreNames(f.kind, tables.genres), f.genre);
  else if (facet === 'language') {
    const codes = tables.languages.map((l) => l.code);
    const code = after(codes, f.language ? f.language.code : null);
    g.language = code ? { code, name: tables.languages[codes.indexOf(code)].name } : null;
  } else if (facet === 'decade') g.decade = after(DECADES, f.decade);
  else if (facet === 'rating') g.rating = after(RATINGS, f.rating);
  return g;
}

export const withPerson = (f, person) => Object.assign({}, f, { person: { id: person.id, name: oneLine(person.name) } });

// A title page's context: its kind, its first genre, and its original language named from the languages table, else by the title's own name for it.
export function fromTitle(ctx, languages) {
  const known = languages.find((l) => l.code === ctx.language_code);
  const name = known ? known.name : oneLine(ctx.language || '');
  return Object.assign(empty(), { kind: ctx.kind, genre: ctx.genre || null, language: ctx.language_code && name ? { code: ctx.language_code, name } : null });
}

export function chips(f) {
  return [
    f.kind !== 'all' ? KIND_NAMES[f.kind] : '',
    f.genre ? oneLine(f.genre) : '',
    f.language ? f.language.name : '',
    f.decade ? `${f.decade}s` : '',
    f.rating ? `★ ${f.rating}+` : '',
    f.person ? f.person.name : '',
  ].filter((c) => c);
}

// One discover call per kind asked: box office is movies only, and a genre is asked of the kinds that have it, by that kind's id.
export function calls(f, genres) {
  return kindsOf(f.kind)
    .filter((k) => f.sort !== 'box-office' || k === 'movie')
    .map((k) => {
      const genre = f.genre ? (genres[k] || []).find((g) => g.name === f.genre) : null;
      if (f.genre && !genre) return null;
      const args = ['api', 'discover', '--kind', k];
      if (f.sort !== 'popular') args.push('--sort', f.sort);
      if (genre) args.push('--genre', String(genre.id));
      if (f.language) args.push('--lang', f.language.code);
      if (f.decade) args.push('--year', years(f.decade));
      if (f.rating) args.push('--min-rating', String(f.rating));
      if (f.person) args.push('--person', String(f.person.id));
      return args;
    })
    .filter((a) => a);
}

// Both kinds' answers as one list: a hit carries no popularity, so popular alternates the two; the other sorts order by rating or year.
export function merge(lists, sort) {
  if (sort === 'popular' || sort === 'box-office') {
    const out = [];
    for (let i = 0; i < Math.max(0, ...lists.map((l) => l.length)); i++) lists.forEach((l) => i < l.length && out.push(l[i]));
    return out;
  }
  const key = sort === 'top-rated' ? (h) => -Number(h.vote || 0) : sort === 'newest' ? (h) => -Number(h.year || 0) : (h) => Number(h.year || 9999);
  return [].concat(...lists).sort((a, b) => key(a) - key(b));
}

// TMDB's department for what a person is known for, as the person picker words it.
const ROLES = { Acting: 'actor', Directing: 'director', Writing: 'writer', Camera: 'cinematographer', Sound: 'composer', Editing: 'editor', Production: 'producer' };
export const roleText = (department) => ROLES[department] || oneLine(department || '').toLowerCase();

// What the facet boxes read: Sort always has a value, the rest read Any until chosen.
export function facets(f) {
  return [
    ['s', 'Sort', f.sort === 'box-office' && f.kind === 'all' ? 'Box office, movies only' : SORT_NAMES[f.sort]],
    ['g', 'Genre', f.genre ? oneLine(f.genre) : 'Any'],
    ['l', 'Language', f.language ? f.language.name : 'Any'],
    ['d', 'Decade', f.decade ? `${f.decade}s` : 'Any'],
    ['r', 'Rating', f.rating ? `${f.rating}+` : 'Any'],
    ['p', 'Person', f.person ? f.person.name : 'Any'],
  ];
}

// The line over the results: the kind, the sort, then each chip past the kind.
export function summary(f) {
  const rest = chips(f).slice(f.kind === 'all' ? 0 : 1);
  return [KIND_NAMES[f.kind], facets(f)[0][2]].concat(rest).join(' · ');
}

// The words each board writes on Browse: Paper's tracked caps, Artboard's sentence case, Blueprint's capitals and brackets.
export function browseText(voice) {
  const caps = voice !== 'plain';
  const up = (s) => (voice === 'bracket' ? s.toUpperCase() : s);
  return {
    label: voice === 'caps' ? 'DEKHO' : 'Dekho',
    page: 'Browse',
    from: (name) => up(`from ${name}`),
    prefilled: (name) => (voice === 'bracket' ? `[PREFILLED FROM ${name.toUpperCase()}]` : `prefilled from ${name}`),
    kind: (kind) => up(KIND_NAMES[kind]),
    count: (n) => up(`${n} title${n === 1 ? '' : 's'}`),
    active: caps ? 'ACTIVE' : 'Active',
    clear: up('x clear all'),
    typing: 'typing…',
    person: voice === 'bracket' ? '[PERSON]' : 'Person',
    columns: caps ? ['TITLE', 'YEAR', 'RATING', 'LANGUAGE', 'GENRES'] : ['Title', 'Year', 'Rating', 'Language', 'Genres'],
    hitCells: (hit) => [up(oneLine(hit.language || '')), up((hit.genres || []).map((g) => oneLine(g)).join(' · '))],
    pick: [['↵', 'add as a filter'], ['esc', 'close']],
    keys: [['f', 'filters'], ['s g l d r p', 'sort genre language decade rating person'], ['t', 'movies / series'], ['x', 'clear'], ['j/k', 'move'], ['↵', 'open'], ['esc', 'back']],
  };
}
