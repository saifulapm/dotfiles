import { test } from 'node:test';
import assert from 'node:assert/strict';
import * as H from './dekho-home.mjs';

const episode = { kind: 'tv', season: 3, episode: 4, position: 1260, duration: 3120 };
const film = { kind: 'movie', season: null, episode: null, position: 4320, duration: 6720 };

test('a series in progress reads its episode and the minutes left', () => {
  assert.equal(H.continueLine('caps', episode), 'S3 E4 · 31 min left');
  assert.equal(H.continueLine('plain', episode), 'S3 E4 · 31 min left');
});

test('a film reads its length and the time left, in hours past the hour', () => {
  assert.equal(H.continueLine('caps', film), '1h 52 · 40 min left');
  assert.equal(H.continueLine('caps', { kind: 'movie', position: 1980, duration: 7440 }), '2h 04 · 1h 31 left');
});

test('Blueprint writes the words left in capitals and keeps the h of an hour', () => {
  assert.equal(H.continueLine('bracket', episode), 'S3 E4 · 31 MIN LEFT');
  assert.equal(H.continueLine('bracket', film), '1h 52 · 40 MIN LEFT');
  assert.equal(H.continueLine('bracket', { kind: 'movie', position: 1980, duration: 7440 }), '2h 04 · 1h 31 LEFT');
});

test('a title mpv never reported a length for says no time left', () => {
  assert.equal(H.continueLine('caps', { kind: 'tv', season: 1, episode: 7, position: 300, duration: 0 }), 'S1 E7');
  assert.equal(H.continueLine('caps', { kind: 'movie', position: 300, duration: 0 }), '');
});

test('a trending title reads its year and its rating to one decimal', () => {
  assert.equal(H.hitLine({ year: '2026', vote: 8.43 }), '2026 · ★ 8.4');
  assert.equal(H.hitLine({ year: '2024', vote: 7 }), '2024 · ★ 7.0');
  assert.equal(H.hitLine({ year: '', vote: 6.5 }), '★ 6.5');
});
