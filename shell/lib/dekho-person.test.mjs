import { test } from 'node:test';
import assert from 'node:assert/strict';
import * as P from './dekho-person.mjs';

const hit = (id, kind, title, year, vote, role) => ({ id, kind, title, year, vote, role });
// The board's Mara Lindqvist, newest first inside each group.
const credits = {
  directing: [hit(101, 'tv', 'The Long Tide', '2024', 8.1, 'Director'), hit(102, 'movie', 'Night Ferry', '2025', 7.3, 'Director')],
  acting: [hit(104, 'movie', 'A Quiet Verdict', '2026', 7.8, 'Judge Hale')],
  writing: [hit(102, 'movie', 'Night Ferry', '2025', 7.3, 'Screenplay')],
};

test('the years of the living read "1971 –", of the dead "1931 – 2004"', () => {
  assert.equal(P.years('1971-03-09', null), '1971 –');
  assert.equal(P.years('1931-05-02', '2004-11-30'), '1931 – 2004');
});

test('a person with no birthday has no years, whatever the deathday says', () => {
  assert.equal(P.years(null, null), '');
  assert.equal(P.years('', ''), '');
  assert.equal(P.years('', '2004-11-30'), '');
});

test('the credit groups come directing, acting, writing, each with its count', () => {
  assert.deepEqual(
    P.groups(credits).map((g) => [g.key, g.count]),
    [['directing', 2], ['acting', 1], ['writing', 1]],
  );
});

test('an acting role reads "as <character>", another group names its job, and a missing role is empty', () => {
  const g = P.groups({ directing: [hit(1, 'tv', 'A', '2024', 1, 'Director')], acting: [hit(2, 'movie', 'B', '2025', 1, 'Judge Hale'), hit(3, 'movie', 'C', '2025', 1, '')], writing: [] });
  assert.equal(g[0].rows[0].roleText, 'Director');
  assert.equal(g[1].rows[0].roleText, 'as Judge Hale');
  assert.equal(g[1].rows[1].roleText, '');
});

test('a vote reads a star and one decimal, and none reads nothing', () => {
  const g = P.groups({ directing: [hit(1, 'tv', 'A', '2024', 8.1, 'Director'), hit(2, 'tv', 'B', '2024', undefined, 'Director')] });
  assert.deepEqual(g[0].rows.map((r) => r.voteText), ['★ 8.1', '']);
});

test('a group with no credits is left out, and a missing credits object gives none', () => {
  assert.deepEqual(P.groups({ directing: [], acting: [hit(2, 'movie', 'B', '2025', 1, 'X')], writing: [] }).map((g) => g.key), ['acting']);
  assert.deepEqual(P.groups(null), []);
});

test('a role or title with a newline, U+202E and ESC reads as one plain line', () => {
  const g = P.groups({ acting: [hit(2, 'movie', 'Salt\nRoad‮\u001b', '2025', 7, 'Nora\nVell‮\u001b')] });
  assert.equal(g[0].rows[0].roleText, 'as Nora Vell');
  assert.equal(g[0].rows[0].titleText, 'Salt Road');
});

test('the rows run on in one list with a heading before each group', () => {
  assert.deepEqual(
    P.lines(P.groups(credits)).map((l) => (l.head ? l.key : l.index)),
    ['directing', 0, 1, 'acting', 2, 'writing', 3],
  );
});

test('a film reads film and a series reads series, shouted only in the bracket voice', () => {
  assert.equal(P.kindText('plain', 'tv'), 'series');
  assert.equal(P.kindText('caps', 'movie'), 'film');
  assert.equal(P.kindText('bracket', 'tv'), 'SERIES');
});

test('the sub-line is the years then the groups the person has credits in, in the voice', () => {
  const g = P.groups({ directing: credits.directing, acting: credits.acting, writing: [] });
  assert.equal(P.subline('plain', '1978-01-01', null, g), '1978 – · Directing · Acting');
  assert.equal(P.subline('caps', '1978-01-01', null, g), '1978 – · DIRECTING · ACTING');
  assert.equal(P.subline('bracket', '1931-01-01', '2004-01-01', g), '1931 – 2004 · DIRECTING · ACTING');
  assert.equal(P.subline('plain', null, null, g), 'Directing · Acting');
});

test('the portrait placeholder carries the first and last initials, and one for a single name', () => {
  assert.equal(P.initials('Mara Lindqvist'), 'ML');
  assert.equal(P.initials('Anna Maria Lopez'), 'AL');
  assert.equal(P.initials('Cher'), 'C');
  assert.equal(P.initials('\n'), '');
});

test('the filter button names the first word of the name', () => {
  assert.equal(P.firstName('Mara Lindqvist'), 'Mara');
  assert.equal(P.firstName(''), '');
});

test('each board words the page its own way', () => {
  assert.deepEqual(
    ['plain', 'caps', 'bracket'].map((v) => [P.personText(v).page, P.personText(v).heading('directing'), P.personText(v).filmography(8), P.personText(v).next]),
    [
      ['person', 'Directing', 'Filmography · 8 credits', 'tab next role'],
      ['person', 'DIRECTING', 'FILMOGRAPHY · 8 CREDITS', 'tab next role'],
      ['PERSON', 'DIRECTING', 'FILMOGRAPHY · 8 CREDITS', 'TAB NEXT ROLE'],
    ],
  );
});
