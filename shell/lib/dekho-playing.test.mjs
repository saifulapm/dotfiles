import { test } from 'node:test';
import assert from 'node:assert/strict';
import * as P from './dekho-playing.mjs';

test("a series' playing label gives its show and S1 · E3, as dekho writes 'Show — S01E03  Name'", () => {
  assert.deepEqual(P.nowPlaying({ event: 'playing', title: 'The Long Tide — S03E04  Quay Nine', kind: 'tv', id: 101 }), { id: 101, kind: 'tv', title: 'The Long Tide', episode: 'S3 · E4' });
  assert.deepEqual(P.nowPlaying({ event: 'playing', title: 'Night — Day — S10E12  A — B', kind: 'tv', id: 7 }), { id: 7, kind: 'tv', title: 'Night — Day', episode: 'S10 · E12' });
});

test("a film's label is its title, with no episode", () => {
  assert.deepEqual(P.nowPlaying({ event: 'playing', title: 'Seven Stations (2026)', kind: 'movie', id: 401 }), { id: 401, kind: 'movie', title: 'Seven Stations (2026)', episode: '' });
});

test('a label anyone at TMDB could have typed draws as one plain line', () => {
  const p = P.nowPlaying({ event: 'playing', title: 'Evil\n‮Tide\u001b[31m — S01E02  x', kind: 'tv', id: 1 });
  assert.equal(p.episode, 'S1 · E2');
  assert.doesNotMatch(p.title, /[\n‮\u001b]/);
});

test('the run plays from its last playing event until it exits; a stop or a failure before playing never shows', () => {
  const playing = { event: 'playing', title: 'Seven Stations (2026)', kind: 'movie', id: 401 };
  assert.equal(P.fromEvents([{ event: 'status' }, { event: 'buffer' }]), null);
  assert.deepEqual(P.fromEvents([{ event: 'status' }, playing]).title, 'Seven Stations (2026)');
  assert.equal(P.fromEvents([playing, { event: 'ended' }, { event: 'exit', code: 0 }]), null);
  assert.equal(P.fromEvents([{ event: 'error', text: 'x' }, { event: 'exit', code: 1 }]), null);
});
