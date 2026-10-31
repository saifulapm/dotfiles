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
  assert.deepEqual([p.fieldRadius, p.ruleDashed, p.library, p.typeLabel, p.chips[0], p.results, p.repeat], [0, false, '', 'TYPE', 'Videos', 'RESULTS', 'repeat off']);
});

test("Artboard's title strip pills YouTube beside a bold view name, and its field and rows are rounded", () => {
  const a = look('artboard');
  assert.deepEqual([a.title.label, a.title.from, a.viewFont, a.viewSize], ['YouTube', 'from the launcher', 'Maple Mono', 14]);
  assert.deepEqual(legend(a, 'search'), ['j/k move', '↵ play video', 'm play audio', 'a add to queue', 's save', 'p add to playlist', 'd/D download audio/video', '/ search', 'tab sidebar', 'esc back']);
  assert.deepEqual([a.fieldRadius, a.rowRadius, a.ruleDashed, a.typeLabel, a.chips[0], a.results, a.repeat], [14, 10, false, '', 'Videos', 'Results', 'repeat off']);
});

test("Blueprint writes its keys bracketed in upper case, its chips in caps, and dashes its rules", () => {
  const b = look('blueprint');
  assert.deepEqual([b.title.label, b.title.from, b.viewFont, b.viewSize], ['YOUTUBE', 'FROM THE LAUNCHER', 'Maple Mono', 12]);
  assert.deepEqual(legend(b, 'search'), ['[J/K] MOVE', '[↵] PLAY VIDEO', '[M] PLAY AUDIO', '[A] ADD TO QUEUE', '[S] SAVE', '[P] ADD TO PLAYLIST', '[D/⇧D] DOWNLOAD AUDIO / VIDEO', '[/] SEARCH', '[TAB] SIDEBAR', '[ESC] BACK']);
  assert.deepEqual([b.fieldRadius, b.ruleDashed, b.library, b.hint, b.chips, b.results, b.repeat], [0, true, 'LIBRARY', '[/]', ['VIDEOS', 'PLAYLISTS', 'CHANNELS'], 'RESULTS', 'REPEAT OFF']);
});

test('an empty view names the key that fills it, and its legend keeps search, sidebar and back', () => {
  for (const name of ['paper', 'artboard', 'blueprint']) {
    const l = look(name);
    assert.deepEqual(l.empty('saved'), { head: 'Nothing saved yet', key: 's', rest: 'saves a video' }, name);
    assert.deepEqual(l.empty('history'), { head: '', key: '', rest: 'Enter or m plays a video' }, name);
    assert.equal(l.empty('search'), null, name);
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
  assert.deepEqual([p.failed.kicker('extraction'), p.failed.kicker('network'), a.failed.kicker('extraction'), b.failed.kicker('extraction')], ['YOUTUBE CHANGED', '', '', '']);
});
