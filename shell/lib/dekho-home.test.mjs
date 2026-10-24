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

test('the saved date is the answer\'s age before now, in local time, as the boards write it', () => {
  const now = new Date(2026, 9, 23, 18, 40).getTime();
  const saved = H.savedAt({ age_secs: 2 * 86400 }, now);
  assert.equal(H.savedDay(saved), '21 Oct');
  assert.equal(H.savedStamp(saved), '21 Oct 18:40');
  assert.equal(H.savedStamp(H.savedAt({ age_secs: 3600 + 5 * 60 }, new Date(2026, 0, 3, 9, 5).getTime())), '3 Jan 08:00');
});

test('an answer with no age has no saved date', () => {
  assert.equal(H.savedAt({}, 1), null);
  assert.equal(H.savedAt(null, 1), null);
});

test('an answer is fresh, a saved copy marked stale, or no answer: null or an error object', () => {
  assert.equal(H.kindOfAnswer({ items: [] }), 'fresh');
  assert.equal(H.kindOfAnswer({ items: [], cached: true, age_secs: 60, stale: false }), 'fresh');
  assert.equal(H.kindOfAnswer({ items: [], cached: true, age_secs: 172800, stale: true }), 'stale');
  assert.equal(H.kindOfAnswer({ error: 'tmdb: network unreachable' }), 'error');
  assert.equal(H.kindOfAnswer(null), 'error');
});

test('the offline words follow each board: the date in the row mark, the retry key, search off', () => {
  const day = new Date(2026, 9, 21, 18, 40);
  assert.equal(H.homeText('caps').saved(day), 'saved 21 Oct');
  assert.equal(H.homeText('plain').saved(day), 'saved 21 Oct');
  assert.equal(H.homeText('bracket').saved(day), 'SAVED 21 OCT');
  assert.deepEqual(H.homeText('caps').retry, ['r', 'retry']);
  assert.deepEqual(H.homeText('bracket').retry, ['[R]', 'RETRY']);
  assert.equal(H.homeText('plain').searchOff, 'Search needs TMDB');
  assert.equal(H.homeText('plain').unreachable, 'TMDB is unreachable.');
  assert.equal(H.homeText('plain').showing(day), 'Showing saved rows from 21 Oct 18:40.');
  assert.equal(H.homeText('plain').showing(null), '');
});
