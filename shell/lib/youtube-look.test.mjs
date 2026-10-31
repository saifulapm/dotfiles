import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { parseToml } from './toml.mjs';
import { youtubeLook } from './youtube-look.mjs';

const theme = (name) => parseToml(readFileSync(new URL(`../../themes/${name}/theme.toml`, import.meta.url), 'utf8'));
const look = (name) => youtubeLook(theme(name));
const legend = (l, view) => l.legend(view).map((k) => `${k.key} ${k.word}`);

test("Paper's title strip is a small caps label over a serif view name, and its legend is tracked caps", () => {
  const p = look('paper');
  assert.deepEqual([p.title.label, p.title.from, p.viewFont, p.viewSize], ['YOUTUBE', 'from the launcher', 'Instrument Serif', 18]);
  assert.deepEqual(legend(p, 'search'), ['J/K MOVE', '↵ PLAY VIDEO', 'M PLAY AUDIO', 'A ADD TO QUEUE', 'S SAVE', 'P ADD TO PLAYLIST', 'D/D DOWNLOAD AUDIO/VIDEO', '/ SEARCH', 'TAB SIDEBAR', 'ESC BACK']);
  assert.deepEqual([p.fieldRadius, p.ruleDashed, p.library, p.typeLabel, p.chips[0], p.results, p.repeat(false), p.repeat(true)], [0, false, '', 'TYPE', 'Videos', 'RESULTS', 'repeat off', 'repeat on']);
});

test("Artboard's title strip pills YouTube beside a bold view name, and its field and rows are rounded", () => {
  const a = look('artboard');
  assert.deepEqual([a.title.label, a.title.from, a.viewFont, a.viewSize], ['YouTube', 'from the launcher', 'Maple Mono', 14]);
  assert.deepEqual(legend(a, 'search'), ['j/k move', '↵ play video', 'm play audio', 'a add to queue', 's save', 'p add to playlist', 'd/D download audio/video', '/ search', 'tab sidebar', 'esc back']);
  assert.deepEqual([a.fieldRadius, a.rowRadius, a.ruleDashed, a.typeLabel, a.chips[0], a.results, a.repeat(false), a.repeat(true)], [14, 10, false, '', 'Videos', 'Results', 'repeat off', 'repeat on']);
});

test("Blueprint writes its keys bracketed in upper case, its chips in caps, and dashes its rules", () => {
  const b = look('blueprint');
  assert.deepEqual([b.title.label, b.title.from, b.viewFont, b.viewSize], ['YOUTUBE', 'FROM THE LAUNCHER', 'Maple Mono', 12]);
  assert.deepEqual(legend(b, 'search'), ['[J/K] MOVE', '[↵] PLAY VIDEO', '[M] PLAY AUDIO', '[A] ADD TO QUEUE', '[S] SAVE', '[P] ADD TO PLAYLIST', '[D/⇧D] DOWNLOAD AUDIO / VIDEO', '[/] SEARCH', '[TAB] SIDEBAR', '[ESC] BACK']);
  assert.deepEqual([b.fieldRadius, b.ruleDashed, b.library, b.hint, b.chips, b.results, b.repeat(false), b.repeat(true)], [0, true, 'LIBRARY', '[/]', ['VIDEOS', 'PLAYLISTS', 'CHANNELS'], 'RESULTS', 'REPEAT OFF', 'REPEAT ON']);
});

test('an empty view names the key that fills it, and its legend keeps search, sidebar and back', () => {
  for (const name of ['paper', 'artboard', 'blueprint']) {
    const l = look(name);
    assert.deepEqual(l.empty('saved'), { head: 'Nothing saved yet', key: 's', rest: 'saves a video' }, name);
    assert.deepEqual(l.empty('history'), { head: '', key: '↵', rest: 'or m plays a video' }, name);
    assert.equal(l.empty('search'), null, name);
    assert.deepEqual(l.empty('channel'), { head: 'No videos on this channel', key: '', rest: '' }, name);
    assert.equal(l.noPlaylists, 'n makes one', name);
  }
  assert.deepEqual(legend(look('paper'), 'saved'), ['/ SEARCH', 'TAB SIDEBAR', 'ESC BACK']);
  assert.deepEqual(legend(look('blueprint'), 'history'), ['[/] SEARCH', '[TAB] SIDEBAR', '[ESC] BACK']);
});

test('the sidebar names Search, Saved and History in every theme, and the field asks for a YouTube search', () => {
  for (const name of ['paper', 'artboard', 'blueprint']) {
    const l = look(name);
    assert.deepEqual(l.places.map((p) => [p.view, p.name]), [['search', 'Search'], ['saved', 'Saved'], ['history', 'History']], name);
    assert.equal(l.title.view('saved'), 'Saved', name);
    assert.equal(l.placeholder, 'Search YouTube', name);
  }
});

test('before the theme loads the window draws with the unthemed look', () => {
  const u = youtubeLook(null);
  assert.equal(u.title.label, 'YOUTUBE');
  assert.equal(u.legend('search').length, 10);
});

// The error boards: the block's headline and retry, Paper's YOUTUBE CHANGED over a stale yt-dlp, and a legend led by try again.
test('a failed search draws the error block and a legend led by try again, as each error board does', () => {
  const failed = (l, view) => l.legend(view, true).map((k) => `${k.key} ${k.word}`);
  const p = look('paper');
  const a = look('artboard');
  const b = look('blueprint');
  assert.deepEqual(failed(p, 'search'), ['↵ TRY AGAIN', '/ SEARCH', 'TAB SIDEBAR', 'ESC BACK']);
  assert.deepEqual(failed(a, 'search'), ['↵ try again', '/ search', 'tab sidebar', 'esc back']);
  assert.deepEqual(failed(b, 'search'), ['[↵] TRY AGAIN', '[/] SEARCH', '[TAB] SIDEBAR', '[ESC] BACK']);
  for (const l of [p, a, b]) assert.equal(l.failed.head, "YouTube didn't give results");
  assert.deepEqual([p.failed.key, p.failed.word, a.failed.key, b.failed.key, b.failed.word], ['↵', 'try again', '↵', '[↵]', 'try again']);
  const stale = { error: 'yt-dlp 2026.10.26 may be behind YouTube: run dots bump, then dots update', kind: 'extraction', raw: '' };
  assert.deepEqual([p.failed.kicker(stale), p.failed.kicker({ error: 'No network.', kind: 'network', raw: '' }), a.failed.kicker(stale), b.failed.kicker(stale)], ['YOUTUBE CHANGED', '', '', '']);
});

// YouTube's own answer about a missing playlist or channel is no change on YouTube's side (walk, 75MMTQMG).
test('Paper heads only a stale yt-dlp block YOUTUBE CHANGED, not YouTube saying a playlist or channel is missing', () => {
  const p = look('paper');
  assert.equal(p.failed.kicker({ error: 'The playlist does not exist.', kind: 'extraction', raw: 'ERROR: [youtube:tab] PLx: YouTube said: The playlist does not exist.' }), '');
  assert.equal(p.failed.kicker({ error: 'YouTube has no such channel or playlist', kind: 'extraction', raw: 'ERROR: HTTP Error 404: Not Found' }), '');
});

// The playlist boards: a Playlist's keys act on it whole, x and Shift+J/K on the item; Blueprint marks the shifted S as it marks D.
test("a Playlist's legend names its whole-playlist keys, and its empty view names p", () => {
  assert.deepEqual(legend(look('paper'), 'playlist'), ['↵ PLAY AS VIDEO', 'M PLAY IN QUEUE', 'S SHUFFLE', 'A ADD TO QUEUE', 'X REMOVE', '⇧J/⇧K MOVE', 'D/D DOWNLOAD MISSING', 'R REPEAT', 'ESC BACK']);
  assert.deepEqual(legend(look('artboard'), 'playlist'), ['↵ play as video', 'm play in queue', 'S shuffle', 'a add to queue', 'x remove', '⇧J/⇧K move', 'd/D download missing', 'r repeat', 'esc back']);
  assert.deepEqual(legend(look('blueprint'), 'playlist'), ['[↵] PLAY AS VIDEO', '[M] PLAY IN QUEUE', '[⇧S] SHUFFLE', '[A] ADD TO QUEUE', '[X] REMOVE', '[⇧J/⇧K] MOVE', '[D/⇧D] DOWNLOAD MISSING', '[R] REPEAT', '[ESC] BACK']);
  for (const name of ['paper', 'artboard', 'blueprint']) assert.deepEqual(look(name).empty('playlist'), { head: '', key: 'p', rest: 'adds a video here' }, name);
});

// The delete board: with the sidebar focused the legend names its keys, and x asks under the row before y deletes.
test('the sidebar legend names n, e, x, open and list, and the delete question counts the videos', () => {
  const sidebar = (l) => l.legend('playlist', false, 'sidebar').map((k) => `${k.key} ${k.word}`);
  assert.deepEqual(sidebar(look('paper')), ['N NEW', 'E RENAME', 'X DELETE', '↵ OPEN', 'TAB LIST']);
  assert.deepEqual(sidebar(look('artboard')), ['n new', 'e rename', 'x delete', '↵ open', 'tab list']);
  assert.deepEqual(sidebar(look('blueprint')), ['[N] NEW', '[E] RENAME', '[X] DELETE', '[↵] OPEN', '[TAB] LIST']);
  assert.deepEqual(legend(look('paper'), 'search'), legend(look('paper'), 'search', false, 'list'));
  const a = look('artboard');
  assert.equal(a.confirm.question('Gym', 25), 'Delete Gym and its 25 videos?');
  assert.equal(a.confirm.question('Deep focus', 0), 'Delete Deep focus and its 0 videos?');
  assert.equal(a.confirm.question('One', 1), 'Delete One and its 1 video?');
  assert.deepEqual(a.confirm.keys.map((k) => `${k.key} ${k.word}`), ['y delete', 'esc keep']);
  assert.deepEqual(look('blueprint').confirm.keys.map((k) => `${k.key} ${k.word}`), ['[Y] DELETE', '[ESC] KEEP']);
  assert.deepEqual(look('paper').confirm.keys.map((k) => `${k.key} ${k.word}`), ['y delete', 'esc keep']);
});

// The pick boards: p's title names the video, a Playlist holding it is marked, n makes a new one, and the picker's legend is its own.
test('the picker names the video, marks a Playlist already holding it, and keeps its own legend', () => {
  const keys = (l) => l.pick.keys.map((k) => `${k.key} ${k.word}`);
  const a = look('artboard');
  assert.equal(a.pick.title('Feather'), 'Add "Feather" to');
  assert.deepEqual([a.pick.chip, a.pick.already, a.pick.newKey, a.pick.newWord], ['p', 'already in', 'n', 'new playlist']);
  assert.deepEqual(keys(a), ['j/k move', '↵ add', 'n new', 'esc cancel']);
  const p = look('paper');
  assert.deepEqual([p.pick.chip, p.pick.already, p.pick.newKey], ['P', 'ALREADY IN', 'n']);
  assert.deepEqual(keys(p), ['J/K MOVE', '↵ ADD', 'N NEW', 'ESC CANCEL']);
  const b = look('blueprint');
  assert.deepEqual([b.pick.chip, b.pick.already, b.pick.newKey], ['PLAYLISTS', 'ALREADY IN ✓', '[N]']);
  assert.deepEqual(keys(b), ['[J/K] MOVE', '[↵] ADD', '[N] NEW', '[ESC] CANCEL']);
});

// The snapshot boards: an opened playlist's s saves it whole, the toast counts what was saved, and the new Playlist is marked.
test('an opened playlist names s save as a playlist, and a snapshot toasts its count and marks the new one', () => {
  const opened = (l) => l.legend('search', false, 'list', 'playlist').map((k) => `${k.key} ${k.word}`);
  assert.deepEqual(opened(look('artboard')), ['j/k move', 's save as a playlist', '↵ play video', 'm play audio', 'a add to queue', '/ search', 'tab sidebar', 'esc back']);
  assert.deepEqual(opened(look('blueprint'))[1], '[S] SAVE AS A PLAYLIST');
  assert.deepEqual(legend(look('artboard'), 'search'), look('artboard').legend('search', false, 'list', 'channel').map((k) => `${k.key} ${k.word}`));
  assert.equal(look('artboard').toast.saved(300), 'Saved as a playlist · 300 videos');
  assert.deepEqual(['paper', 'artboard', 'blueprint'].map((n) => look(n).fresh), ['NEW', 'new', 'NEW']);
});

test('an unavailable item reads Video unavailable and its reason', () => {
  for (const name of ['paper', 'artboard', 'blueprint']) assert.equal(look(name).unavailable('made private'), 'Video unavailable · made private', name);
});

// A long name, a hostile playlist's title say, is cut so the question still ends with what it deletes.
test('the delete question cuts a long name and keeps its count', () => {
  const q = look('blueprint').confirm.question('H'.repeat(316), 14);
  assert.equal(q, `Delete ${'H'.repeat(39)}… and its 14 videos?`);
  assert.equal(look('blueprint').confirm.question('H'.repeat(40), 1), `Delete ${'H'.repeat(40)} and its 1 video?`);
});
