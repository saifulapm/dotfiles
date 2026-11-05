import { test } from 'node:test';
import assert from 'node:assert/strict';
import { schemeTokens } from './colorscheme-file.mjs';
import { youtubeLook } from './youtube-look.mjs';

const look = (name) => youtubeLook(schemeTokens(name));
const legend = (l, view) => l.legend(view).map((k) => `${k.key} ${k.word}`);

test('the title strip pills YouTube beside a bold view name, and its field and rows are rounded', () => {
  const a = look('artboard');
  assert.deepEqual([a.title.label, a.title.from, a.viewFont, a.viewSize], ['YouTube', 'from the launcher', 'Maple Mono', 14]);
  assert.deepEqual(legend(a, 'search'), ['j/k move', '↵ play video', 'm play audio', 'a add to queue', 's save', 'p add to playlist', 'd/D download audio/video', '/ search', 'tab sidebar', 'esc back']);
  assert.deepEqual([a.fieldRadius, a.rowRadius, a.hint, a.chips, a.results, a.repeat(false), a.repeat(true)], [14, 10, '/', ['Videos', 'Playlists', 'Channels'], 'Results', 'repeat off', 'repeat on']);
});

test('an empty view names the key that fills it, and its legend keeps search, sidebar and back', () => {
  const l = look('artboard');
  assert.deepEqual(l.empty('saved'), { head: 'Nothing saved yet', key: 's', rest: 'saves a video' });
  assert.deepEqual(l.empty('history'), { head: '', key: '↵', rest: 'or m plays a video' });
  assert.equal(l.empty('search'), null);
  assert.deepEqual(l.empty('channel'), { head: 'No videos on this channel', key: '', rest: '' });
  assert.equal(l.noPlaylists, 'n makes one');
  assert.deepEqual(legend(l, 'saved'), ['/ search', 'tab sidebar', 'esc back']);
});

test('the sidebar names Search, Saved and History, and the field asks for a YouTube search', () => {
  const l = look('artboard');
  assert.deepEqual(l.places.map((p) => [p.view, p.name]), [['search', 'Search'], ['saved', 'Saved'], ['history', 'History']]);
  assert.equal(l.title.view('saved'), 'Saved');
  assert.equal(l.placeholder, 'Search YouTube');
});

test('before the colorscheme loads the window draws the plain title and the full legend', () => {
  const u = youtubeLook(null);
  assert.equal(u.title.label, 'YouTube');
  assert.equal(u.legend('search').length, 10);
});

test('a failed search draws the error block and a legend led by try again', () => {
  const a = look('artboard');
  assert.deepEqual(a.legend('search', true).map((k) => `${k.key} ${k.word}`), ['↵ try again', '/ search', 'tab sidebar', 'esc back']);
  assert.deepEqual([a.failed.head, a.failed.key, a.failed.word], ["YouTube didn't give results", '↵', 'try again']);
});

// A Playlist's keys act on it whole, x and Shift+J/K on the item.
test("a Playlist's legend names its whole-playlist keys, and its empty view names p", () => {
  const a = look('artboard');
  assert.deepEqual(legend(a, 'playlist'), ['↵ play as video', 'm play in queue', 'S shuffle', 'a add to queue', 'x remove', '⇧J/⇧K move', 'd/D download missing', 'r repeat', 'esc back']);
  assert.deepEqual(a.empty('playlist'), { head: '', key: 'p', rest: 'adds a video here' });
});

// With the sidebar focused the legend names its keys, and x asks under the row before y deletes.
test('the sidebar legend names n, e, x, open and list, and the delete question counts the videos', () => {
  const a = look('artboard');
  assert.deepEqual(a.legend('playlist', false, 'sidebar').map((k) => `${k.key} ${k.word}`), ['n new', 'e rename', 'x delete', '↵ open', 'tab list']);
  assert.deepEqual(legend(a, 'search'), a.legend('search', false, 'list').map((k) => `${k.key} ${k.word}`));
  assert.equal(a.confirm.question('Gym', 25), 'Delete Gym and its 25 videos?');
  assert.equal(a.confirm.question('Deep focus', 0), 'Delete Deep focus and its 0 videos?');
  assert.equal(a.confirm.question('One', 1), 'Delete One and its 1 video?');
  assert.deepEqual(a.confirm.keys.map((k) => `${k.key} ${k.word}`), ['y delete', 'esc keep']);
});

// p's title names the video, a Playlist holding it is marked, n makes a new one, and the picker's legend is its own.
test('the picker names the video, marks a Playlist already holding it, and keeps its own legend', () => {
  const a = look('artboard');
  assert.equal(a.pick.title('Feather'), 'Add "Feather" to');
  assert.deepEqual([a.pick.chip, a.pick.already, a.pick.newKey, a.pick.newWord], ['p', 'already in', 'n', 'new playlist']);
  assert.deepEqual(a.pick.keys.map((k) => `${k.key} ${k.word}`), ['j/k move', '↵ add', 'n new', 'esc cancel']);
});

// An opened playlist's s saves it whole, the toast counts what was saved, and the new Playlist is marked.
test('an opened playlist names s save as a playlist, and a snapshot toasts its count and marks the new one', () => {
  const a = look('artboard');
  assert.deepEqual(a.legend('search', false, 'list', 'playlist').map((k) => `${k.key} ${k.word}`), ['j/k move', 's save as a playlist', '↵ play video', 'm play audio', 'a add to queue', '/ search', 'tab sidebar', 'esc back']);
  assert.deepEqual(legend(a, 'search'), a.legend('search', false, 'list', 'channel').map((k) => `${k.key} ${k.word}`));
  assert.equal(a.toast.saved(300), 'Saved as a playlist · 300 videos');
  assert.equal(a.fresh, 'new');
});

test('an unavailable item reads Video unavailable and its reason', () => {
  assert.equal(look('artboard').unavailable('made private'), 'Video unavailable · made private');
});

// A long name, a hostile playlist's title say, is cut so the question still ends with what it deletes.
test('the delete question cuts a long name and keeps its count', () => {
  const a = look('artboard');
  assert.equal(a.confirm.question('H'.repeat(316), 14), `Delete ${'H'.repeat(39)}… and its 14 videos?`);
  assert.equal(a.confirm.question('H'.repeat(40), 1), `Delete ${'H'.repeat(40)} and its 1 video?`);
});

test('the download mark is a deep arrow in a grey tile, and the tints are light', () => {
  const a = look('artboard');
  assert.deepEqual(a.mark, { size: 12, stroke: '#2638C9', width: 2, tile: { width: 22, height: 20, radius: 6, color: '#F2F3F6' } });
  assert.deepEqual([a.tint.tint, a.tint.errInk, a.tint.errText, a.retryColor], ['#EEF1FF', '#B4380B', '#2B2F36', '#B4380B']);
  assert.deepEqual(youtubeLook(null).mark.tile.color, '#F2F3F6');
});

test('a failed download reads in the channel line with the key that retries it, in the error colour', () => {
  assert.deepEqual([look('artboard').retry('disk full'), look('artboard').retryColor], ['download failed · disk full · ↵ retry', '#B4380B']);
});
