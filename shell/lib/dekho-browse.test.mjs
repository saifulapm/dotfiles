import { test } from 'node:test';
import assert from 'node:assert/strict';
import * as B from './dekho-browse.mjs';

const genres = {
  movie: [{ id: 28, name: 'Action' }, { id: 18, name: 'Drama' }, { id: 27, name: 'Horror' }],
  tv: [{ id: 10759, name: 'Action & Adventure' }, { id: 18, name: 'Drama' }, { id: 10762, name: 'Kids' }],
};
const languages = [{ code: 'en', name: 'English' }, { code: 'sv', name: 'Swedish' }, { code: 'ko', name: 'Korean' }];
const tables = { genres, languages };
const tv = { ...B.empty(), kind: 'tv' };

test('nothing chosen asks both kinds by popularity and draws no chip', () => {
  assert.deepEqual(B.calls(B.empty(), genres), [['api', 'discover', '--kind', 'movie'], ['api', 'discover', '--kind', 'tv']]);
  assert.deepEqual(B.chips(B.empty()), []);
});

test('t walks all, movies, series and back to all', () => {
  const movies = B.next(B.empty(), 'kind', tables);
  assert.deepEqual(B.calls(movies, genres), [['api', 'discover', '--kind', 'movie']]);
  assert.deepEqual(B.chips(movies), ['Movies']);
  const series = B.next(movies, 'kind', tables);
  assert.deepEqual(B.calls(series, genres), [['api', 'discover', '--kind', 'tv']]);
  assert.deepEqual(B.chips(series), ['Series']);
  assert.equal(B.next(series, 'kind', tables).kind, 'all');
});

test('a click on a kind tab picks that kind, and drops what the kind cannot have', () => {
  const box = { ...B.empty(), sort: 'box-office', genre: 'Action' };
  const series = B.withKind(box, 'tv', tables);
  assert.deepEqual([series.kind, series.sort, series.genre], ['tv', 'popular', null]);
  assert.equal(B.withKind({ ...B.empty(), genre: 'Kids' }, 'tv', tables).genre, 'Kids');
  assert.equal(B.withKind(series, 'all', tables).kind, 'all');
});

test('s walks the sorts and asks each by its flag', () => {
  const sorts = [];
  let f = { ...B.empty(), kind: 'movie' };
  for (let i = 0; i < 5; i++) {
    f = B.next(f, 'sort', tables);
    sorts.push(B.calls(f, genres)[0].slice(4).join(' '));
  }
  assert.deepEqual(sorts, ['--sort top-rated', '--sort newest', '--sort oldest', '--sort box-office', '']);
});

test('box office asks movies only, and a series skips it', () => {
  assert.deepEqual(B.calls({ ...B.empty(), sort: 'box-office' }, genres), [['api', 'discover', '--kind', 'movie', '--sort', 'box-office']]);
  assert.equal(B.next({ ...tv, sort: 'oldest' }, 'sort', tables).sort, 'popular');
});

test('g walks the kind genres and asks each kind by its own id', () => {
  const action = B.next({ ...B.empty(), kind: 'movie' }, 'genre', tables);
  assert.deepEqual(B.calls(action, genres), [['api', 'discover', '--kind', 'movie', '--genre', '28']]);
  assert.deepEqual(B.chips(action), ['Movies', 'Action']);
  const drama = { ...B.empty(), genre: 'Drama' };
  assert.deepEqual(B.calls(drama, genres), [['api', 'discover', '--kind', 'movie', '--genre', '18'], ['api', 'discover', '--kind', 'tv', '--genre', '18']]);
  // A genre only series have is asked of series alone.
  assert.deepEqual(B.calls({ ...B.empty(), genre: 'Kids' }, genres), [['api', 'discover', '--kind', 'tv', '--genre', '10762']]);
  assert.equal(B.next({ ...B.empty(), kind: 'tv', genre: 'Kids' }, 'genre', tables).genre, null);
});

test('l walks the languages by name and asks by the code', () => {
  const f = B.next(tv, 'language', tables);
  assert.deepEqual(B.calls(f, genres), [['api', 'discover', '--kind', 'tv', '--lang', 'en']]);
  assert.deepEqual(B.chips(f), ['Series', 'English']);
  assert.equal(B.next({ ...tv, language: { code: 'ko', name: 'Korean' } }, 'language', tables).language, null);
});

test('d walks 1970s to 2020s, a decade asked as its ten years', () => {
  assert.equal(B.years(1990), '1990-1999');
  const seventies = B.next(tv, 'decade', tables);
  assert.deepEqual(B.calls(seventies, genres), [['api', 'discover', '--kind', 'tv', '--year', '1970-1979']]);
  assert.deepEqual(B.chips({ ...tv, decade: 1990 }), ['Series', '1990s']);
  assert.equal(B.next({ ...tv, decade: 2020 }, 'decade', tables).decade, null);
});

test('r walks 6+, 7+ and 8+ as a minimum rating', () => {
  const six = B.next(tv, 'rating', tables);
  assert.deepEqual(B.calls(six, genres), [['api', 'discover', '--kind', 'tv', '--min-rating', '6']]);
  assert.deepEqual(B.chips({ ...tv, rating: 7 }), ['Series', '★ 7+']);
  assert.equal(B.next({ ...tv, rating: 8 }, 'rating', tables).rating, null);
});

test('p asks by the person id and draws the name', () => {
  const f = B.withPerson(tv, { id: 1001, name: 'Mara\nLindqvist' });
  assert.deepEqual(B.calls(f, genres), [['api', 'discover', '--kind', 'tv', '--person', '1001']]);
  assert.deepEqual(B.chips(f), ['Series', 'Mara Lindqvist']);
});

test('every filter at once goes into one call per kind', () => {
  const f = { kind: 'tv', sort: 'top-rated', genre: 'Drama', language: { code: 'sv', name: 'Swedish' }, decade: 1990, rating: 7, person: { id: 1001, name: 'Mara' } };
  assert.deepEqual(B.calls(f, genres), [['api', 'discover', '--kind', 'tv', '--sort', 'top-rated', '--genre', '18', '--lang', 'sv', '--year', '1990-1999', '--min-rating', '7', '--person', '1001']]);
  assert.deepEqual(B.chips(f), ['Series', 'Drama', 'Swedish', '1990s', '★ 7+', 'Mara']);
});

test('x clears every filter back to the unfiltered set', () => {
  const f = { kind: 'tv', sort: 'top-rated', genre: 'Drama', language: { code: 'sv', name: 'Swedish' }, decade: 1990, rating: 7, person: { id: 1001, name: 'Mara' } };
  const cleared = B.clear(f);
  assert.deepEqual(B.chips(cleared), []);
  assert.deepEqual(B.calls(cleared, genres), [['api', 'discover', '--kind', 'movie'], ['api', 'discover', '--kind', 'tv']]);
});

test("a title's kind, genre and language become its chips, the language by name", () => {
  const f = B.fromTitle({ kind: 'tv', genre: 'Drama', language_code: 'sv' }, languages);
  assert.deepEqual(B.chips(f), ['Series', 'Drama', 'Swedish']);
  assert.deepEqual(B.calls(f, genres), [['api', 'discover', '--kind', 'tv', '--genre', '18', '--lang', 'sv']]);
});

test("a title language the table lacks draws the title's own name for it, never the code", () => {
  const f = B.fromTitle({ kind: 'movie', genre: null, language: 'Icelandic', language_code: 'is' }, languages);
  assert.deepEqual(B.chips(f), ['Movies', 'Icelandic']);
  assert.deepEqual(B.chips(B.fromTitle({ kind: 'movie', language_code: 'is' }, languages)), ['Movies']);
});

test('both kinds interleave by the sort: popular alternates, top rated by rating, newest and oldest by year', () => {
  const movies = [{ id: 1, year: '2020', vote: 7 }, { id: 2, year: '2010', vote: 6 }];
  const series = [{ id: 3, year: '2024', vote: 8 }, { id: 4, year: '2000', vote: 5 }, { id: 5, year: '1999', vote: 9 }];
  const ids = (sort) => B.merge([movies, series], sort).map((h) => h.id);
  assert.deepEqual(ids('popular'), [1, 3, 2, 4, 5]);
  assert.deepEqual(ids('top-rated'), [5, 3, 1, 2, 4]);
  assert.deepEqual(ids('newest'), [3, 1, 2, 4, 5]);
  assert.deepEqual(ids('oldest'), [5, 4, 2, 1, 3]);
});

// The board's last two columns: the hit's language and its genres, capitals in Blueprint only, one line each.
test('a result row names its language and genres as each board writes them', () => {
  const hit = { language: 'English', genres: ['Drama', 'Mystery'] };
  assert.deepEqual(B.browseText('caps').columns, ['TITLE', 'YEAR', 'RATING', 'LANGUAGE', 'GENRES']);
  assert.deepEqual(B.browseText('plain').columns, ['Title', 'Year', 'Rating', 'Language', 'Genres']);
  assert.deepEqual(B.browseText('caps').hitCells(hit), ['English', 'Drama · Mystery']);
  assert.deepEqual(B.browseText('plain').hitCells(hit), ['English', 'Drama · Mystery']);
  assert.deepEqual(B.browseText('bracket').hitCells(hit), ['ENGLISH', 'DRAMA · MYSTERY']);
  assert.deepEqual(B.browseText('plain').hitCells({}), ['', '']);
  assert.deepEqual(B.browseText('plain').hitCells({ language: 'Sw\nedish‮', genres: ['Dra\u001bma'] }), ['Sw edish', 'Dra ma']);
});
