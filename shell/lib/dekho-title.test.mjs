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
  assert.equal(T.nextUp([ep(1, '2026-10-30', false), ep(2, '', false)], today), -1);
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
});

test('each board writes the next-up tag its own way', () => {
  assert.equal(T.titleText('caps').nextUp, 'NEXT UP');
  assert.equal(T.titleText('plain').nextUp, 'next up');
  assert.equal(T.titleText('bracket').nextUp, '[NEXT UP]');
  assert.equal(T.titleText('plain').crew, 'Crew');
  assert.equal(T.titleText('caps').crew, 'CREW');
});
