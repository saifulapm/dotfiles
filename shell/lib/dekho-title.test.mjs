import { test } from 'node:test';
import assert from 'node:assert/strict';
import * as T from './dekho-title.mjs';

const today = '2026-10-23';
const ep = (episode, air_date, watched) => ({ season: 3, episode, air_date, watched });
// The board's S3: three watched, one aired today, four to come.
const s3 = [ep(1, '2026-10-02', true), ep(2, '2026-10-09', true), ep(3, '2026-10-16', true), ep(4, '2026-10-23', false), ep(5, '2026-10-30', false), ep(6, '2026-11-06', false), ep(7, '2026-11-13', false), ep(8, '2026-11-20', false)];

test('next up is the first aired episode not watched, one aired today counting as aired', () => {
  assert.equal(T.nextUp(s3, today), 3);
});

test('a season all watched, or none aired yet, has no next up', () => {
  assert.equal(T.nextUp([ep(1, '2026-01-01', true), ep(2, '2026-01-08', true)], today), -1);
  assert.equal(T.nextUp([ep(1, '2026-10-30', false), ep(2, '2026-11-06', false)], today), -1);
});

test('an unwatched episode before a watched one is still next up', () => {
  assert.equal(T.nextUp([ep(1, '2026-01-01', true), ep(2, '2026-01-08', false), ep(3, '2026-01-15', true), ep(4, '2026-01-22', false)], today), 1);
});

test('the page opens on the season holding next up, else the last season', () => {
  const done = [ep(1, '2025-01-01', true)];
  const later = [ep(1, '2027-01-01', false)];
  assert.equal(T.startSeason({ 1: done, 2: done, 3: s3, 4: later }, today), 3);
  assert.equal(T.startSeason({ 1: done, 2: done }, today), 2);
});

test('an aired episode reads its day and month, one to come reads airs and its day', () => {
  assert.equal(T.dateText('caps', '2026-10-02', today), '2 Oct');
  assert.equal(T.dateText('plain', '2026-10-30', today), 'airs 30 Oct');
  assert.equal(T.dateText('bracket', '2026-11-06', today), 'AIRS 6 NOV');
  assert.equal(T.dateText('bracket', '2026-10-23', today), '23 OCT');
  assert.equal(T.dateText('caps', '', today), '');
});

test('the count reads how many of the season are watched', () => {
  assert.equal(T.watchedText('caps', s3), '3 of 8 watched');
  assert.equal(T.watchedText('bracket', s3), '3 OF 8 WATCHED');
});

test('the crew keeps the director, the writers and the composer, in that order', () => {
  const crew = [
    { id: 1, name: 'Ann Exec', job: 'Executive Producer' },
    { id: 2, name: 'Ingrid Sol', job: 'Composer' },
    { id: 3, name: 'Tomas Eze', job: 'Writer' },
    { id: 4, name: 'Mara Lindqvist', job: 'Director' },
    { id: 5, name: 'Cal Maker', job: 'Creator' },
    { id: 6, name: 'Sam Page', job: 'Screenplay' },
  ];
  assert.deepEqual(T.notableCrew(crew), [
    { id: 4, name: 'Mara Lindqvist', role: 'director' },
    { id: 3, name: 'Tomas Eze', role: 'writer' },
    { id: 6, name: 'Sam Page', role: 'writer' },
    { id: 2, name: 'Ingrid Sol', role: 'composer' },
  ]);
});

test('the chips are the genres then the original language', () => {
  assert.deepEqual(T.chips({ genres: ['Drama', 'Mystery'], language: 'English', languages: ['English', 'Swedish'] }), ['Drama', 'Mystery', 'English']);
  assert.deepEqual(T.chips({ genres: [], language: '', languages: ['Swedish'] }), ['Swedish']);
});

test('the lines under the title read its years, rating and episode length, and its genres and seasons', () => {
  const show = { kind: 'tv', year: '2024', vote: 8.14, runtime: 3000, genres: ['Drama', 'Mystery'], season_count: 4, in_production: true };
  assert.equal(T.metaText('caps', show), '2024 – · ★ 8.1 · 50 min episodes');
  assert.equal(T.metaText('bracket', show), '2024 – · ★ 8.1 · 50 MIN EPISODES');
  assert.equal(T.sideText('caps', show), 'Drama · Mystery · 4 seasons');
  assert.equal(T.sideText('bracket', show), 'DRAMA · MYSTERY · 4 SEASONS');
  assert.equal(T.metaText('caps', { kind: 'tv', year: '2019', vote: 7, runtime: 2700, in_production: false, last_air: '2021-05-02' }), '2019 – 2021 · ★ 7.0 · 45 min episodes');
  assert.equal(T.metaText('plain', { kind: 'movie', year: '2026', vote: 7.8, runtime: 6720 }), '2026 · ★ 7.8 · 1h 52');
  assert.equal(T.metaText('plain', { kind: 'movie', year: '2026', vote: 0, runtime: 6720 }), '2026 · 1h 52');
});

test('each board writes the next-up tag its own way', () => {
  assert.equal(T.titleText('caps').nextUp, 'NEXT UP');
  assert.equal(T.titleText('plain').nextUp, 'next up');
  assert.equal(T.titleText('bracket').nextUp, '[NEXT UP]');
  assert.equal(T.titleText('plain').crew, 'Crew');
  assert.equal(T.titleText('caps').crew, 'CREW');
});

// Only a date after today holds an episode back; TMDB leaves some specials and older episodes undated.
test('an episode with no air date can be opened and be next up, and draws no date', () => {
  const items = [
    { episode: 1, air_date: null, watched: false },
    { episode: 2, air_date: '2099-01-01', watched: false },
  ];
  assert.equal(T.aired(items[0], '2026-10-24'), true);
  assert.equal(T.nextUp(items, '2026-10-24'), 0);
  assert.equal(T.dateText('caps', null, '2026-10-24'), '');
});

const seen = [
  { id: 101, kind: 'tv', season: 3, episode: 4, position: 1260, duration: 3120, finished: false },
  { id: 202, kind: 'movie', position: 4320, duration: 6720, finished: false },
  { id: 205, kind: 'movie', position: 6700, duration: 6720, finished: true },
];

test("a title is being watched when history holds it by id and kind and it is not finished", () => {
  assert.equal(T.watching(seen, { id: 202, kind: 'movie' }), seen[1]);
  assert.equal(T.watching(seen, { id: 202, kind: 'tv' }), null);
  assert.equal(T.watching(seen, { id: 205, kind: 'movie' }), null);
  assert.equal(T.watching(null, { id: 101, kind: 'tv' }), null);
});

test('Play always shows; Resume joins it with a series\' episode and the time left, never RESUME twice', () => {
  assert.deepEqual(T.buttons('plain', null), [{ id: 'play', text: '▶ Play' }]);
  assert.deepEqual(T.buttons('caps', seen[1]), [{ id: 'play', text: '▶ Play' }, { id: 'resume', text: '▶ Resume · 40 min left' }]);
  assert.deepEqual(T.buttons('plain', seen[0]).map((b) => b.text), ['▶ Play', '▶ Resume · S3 · E4 · 31 min left']);
  assert.deepEqual(T.buttons('bracket', seen[0]).map((b) => b.text), ['▶ PLAY', '▶ RESUME · S3 · E4 · 31 MIN LEFT']);
});

test('a title with a trailer adds Trailer after Play and Resume; a null or empty one adds none', () => {
  const url = 'https://www.youtube.com/watch?v=abc';
  assert.deepEqual(T.buttons('plain', null, url), [{ id: 'play', text: '▶ Play' }, { id: 'trailer', text: '▶ Trailer' }]);
  assert.deepEqual(T.buttons('caps', seen[1], url).map((b) => b.id), ['play', 'resume', 'trailer']);
  assert.deepEqual(T.buttons('bracket', null, url).map((b) => b.text), ['▶ PLAY', '▶ TRAILER']);
  assert.deepEqual(T.buttons('plain', null, null), [{ id: 'play', text: '▶ Play' }]);
  assert.deepEqual(T.buttons('plain', null, ''), [{ id: 'play', text: '▶ Play' }]);
});

test('the footer names r for resume, t for trailer, and tab reaches the buttons', () => {
  const keys = T.titleText('plain').keys;
  assert.ok(keys.some(([k, w]) => k === 'r' && w === 'resume'));
  assert.deepEqual(keys[keys.findIndex(([k]) => k === 'r') + 1], ['t', 'trailer']);
  assert.ok(keys.some(([k, w]) => k === 'tab' && w.startsWith('buttons')));
});

test('the tagline is the title\'s own text, trimmed, and empty when it has none', () => {
  assert.equal(T.tagline({ tagline: 'The water remembers.' }), 'The water remembers.');
  assert.equal(T.tagline({ tagline: '  Hold on.  ' }), 'Hold on.');
  assert.equal(T.tagline({ tagline: '' }), '');
  assert.equal(T.tagline({ tagline: null }), '');
  assert.equal(T.tagline({}), '');
  assert.equal(T.tagline({ tagline: 7 }), '');
});

test('a series links TMDB under /tv/ and IMDb, in the voice\'s words', () => {
  const tide = { id: 101, kind: 'tv', imdb_id: 'tt0000101', homepage: '' };
  assert.deepEqual(T.links('plain', tide), [
    { id: 'tmdb', text: 'TMDB', url: 'https://www.themoviedb.org/tv/101' },
    { id: 'imdb', text: 'IMDb', url: 'https://www.imdb.com/title/tt0000101' },
  ]);
  assert.deepEqual(T.links('bracket', tide).map((l) => l.text), ['TMDB', 'IMDB']);
});

test('a film links TMDB under /movie/ and its http(s) homepage last', () => {
  const film = { id: 400, kind: 'movie', imdb_id: 'tt0000400', homepage: 'https://example.org/a-quiet-verdict' };
  assert.deepEqual(T.links('caps', film).map((l) => [l.id, l.text, l.url]), [
    ['tmdb', 'TMDB', 'https://www.themoviedb.org/movie/400'],
    ['imdb', 'IMDb', 'https://www.imdb.com/title/tt0000400'],
    ['homepage', 'Homepage', 'https://example.org/a-quiet-verdict'],
  ]);
  assert.equal(T.links('bracket', film)[2].text, 'HOMEPAGE');
  assert.equal(T.links('plain', { ...film, homepage: 'http://example.org/' })[2].url, 'http://example.org/');
});

test('a missing or malformed imdb id hides IMDb, and a homepage that is not http(s) shows no link', () => {
  const base = { id: 300, kind: 'tv' };
  const ids = (t) => T.links('plain', { ...base, ...t }).map((l) => l.id);
  assert.deepEqual(ids({}), ['tmdb']);
  assert.deepEqual(ids({ imdb_id: '', homepage: '' }), ['tmdb']);
  assert.deepEqual(ids({ imdb_id: 'tt12/../x' }), ['tmdb']);
  assert.deepEqual(ids({ imdb_id: 'tt1\n' }), ['tmdb']);
  assert.deepEqual(ids({ homepage: 'javascript:alert(1)' }), ['tmdb']);
  assert.deepEqual(ids({ homepage: 'ftp://example.org/' }), ['tmdb']);
  assert.deepEqual(ids({ homepage: 'https://' }), ['tmdb']);
  assert.deepEqual(ids({ homepage: 'https://a b' }), ['tmdb']);
  assert.deepEqual(ids({ homepage: 'https://a.org/‮x' }), ['tmdb']);
});
