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

test("the bar's words in each board's voice", () => {
  assert.deepEqual(P.barText('plain'), { tag: 'Now playing', keys: [['⇧S', 'stop']] });
  assert.equal(P.barText('caps').tag, 'NOW PLAYING');
  assert.equal(P.barText('bracket').tag, '[NOW PLAYING]');
});

const win = (pid, title, app_id = 'mpv') => ({ id: pid * 10, pid, app_id, title });
const tide = { id: 101, kind: 'tv', title: 'The Long Tide', episode: 'S3 · E4' };

test("a series moves on to the episode its own mpv window names, as mpv titles it '<media-title> - mpv'", () => {
  const text = JSON.stringify([win(7, 'The Long Tide — S03E05  Neap - mpv'), win(9, 'Seven Stations (2026) — Trailer - mpv')]);
  assert.deepEqual(P.fromWindow(tide, text, [7]), { id: 101, kind: 'tv', title: 'The Long Tide', episode: 'S3 · E5' });
  // The fake's stand-in titles its window with the bare label.
  assert.equal(P.fromWindow(tide, JSON.stringify([win(7, 'The Long Tide — S03E06  Spring')]), [7]).episode, 'S3 · E6');
});

test("only the film unit's own mpv window counts, and anything else leaves what plays as it was", () => {
  const other = JSON.stringify([win(9, 'The Long Tide — S03E05  Neap - mpv')]);
  assert.equal(P.fromWindow(tide, other, [7]), tide);
  assert.equal(P.fromWindow(tide, JSON.stringify([win(7, 'No file - mpv')]), [7]), tide);
  assert.equal(P.fromWindow(tide, JSON.stringify([win(7, 'Another Show — S01E02  x - mpv')]), [7]), tide);
  assert.equal(P.fromWindow(tide, 'not json', [7]), tide);
  const film = { id: 401, kind: 'movie', title: 'Seven Stations (2026)', episode: '' };
  assert.equal(P.fromWindow(film, JSON.stringify([win(7, 'Seven Stations (2026) - mpv')]), [7]), film);
  assert.equal(P.fromWindow(null, JSON.stringify([win(7, 'The Long Tide — S03E05  Neap')]), [7]), null);
});
