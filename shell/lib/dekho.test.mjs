import { test } from 'node:test';
import assert from 'node:assert/strict';
import * as D from './dekho.mjs';

test('a title with a newline, U+202E and ESC is one line without them', () => {
  assert.equal(D.title('Low\nTide‮\u001b Radio'), 'Low Tide Radio');
});

test('a 300-character title stays whole for the drawn item to elide', () => {
  const long = 'x'.repeat(300);
  assert.equal(D.title(long), long);
  assert.equal(D.title('a\n'.repeat(150)), Array(150).fill('a').join(' '));
});

test('the backend\'s answer is its one JSON object, or null for anything else', () => {
  assert.deepEqual(D.answer('{"items":[{"id":7}]}\n'), { items: [{ id: 7 }] });
  assert.equal(D.answer(''), null);
  assert.equal(D.answer('error: no network'), null);
  assert.equal(D.answer('[1,2]'), null);
});

// TMDB gives 0 to a title nobody has voted on yet, which would read as the worst rating (#2EW5X9NG).
test('a rating reads a star and one decimal, and no votes read nothing', () => {
  assert.equal(D.stars(8.43), '★ 8.4');
  assert.equal(D.stars(7), '★ 7.0');
  assert.equal(D.stars(0), '');
  assert.equal(D.stars(undefined), '');
});

// The real dekho fails a whole prefetch call on a path it refuses, and the file it names becomes a file URL.
test('a picture path is /name.ext of letters, digits, _ and -, and nothing else', () => {
  assert.ok(D.picturePath('/sJZcy8QsOPuRPiCfoCWVB3r9Ohg.jpg'));
  assert.ok(D.picturePath('/a_b-c.png'));
  for (const p of [null, undefined, '', '/', 'p1.jpg', '/a/b.jpg', '/../x.jpg', '/a.jpg?x', '/a b.jpg', '/a#.jpg', '/noext', 7])
    assert.ok(!D.picturePath(p), String(p));
});

test('one prefetch asks for each well-formed path once, past those already on disk', () => {
  assert.deepEqual(D.wanted(['/a.jpg', null, '/b.jpg', '/a.jpg', '', '/x/y.jpg', '/c.jpg'], { '/c.jpg': '/cache/c.jpg' }), ['/a.jpg', '/b.jpg']);
  assert.deepEqual(D.wanted([], {}), []);
});

test('an answer adds the files it lists for the paths asked, and nothing else', () => {
  const held = { '/old.jpg': '/cache/old.jpg' };
  const answer = { dir: '/cache', files: { '/a.jpg': '/cache/a.jpg', '/never-asked.jpg': '/cache/n.jpg', '/b.jpg': 7 } };
  assert.deepEqual(D.withFiles(held, answer, ['/a.jpg', '/b.jpg', '/gone.jpg']), { '/old.jpg': '/cache/old.jpg', '/a.jpg': '/cache/a.jpg' });
  assert.deepEqual(held, { '/old.jpg': '/cache/old.jpg' });
  assert.deepEqual(D.withFiles(held, null, ['/a.jpg']), held);
  assert.deepEqual(D.withFiles(held, { error: 'tmdb: network unreachable' }, ['/a.jpg']), held);
});

// The backend renames a whole download into its size's folder, so a file listed there is a picture on disk; a .part is one still arriving.
test('a cache folder\'s files join what is on disk, by the path each answers to', () => {
  const held = { '/a.jpg': '/c/w342/a.jpg' };
  assert.deepEqual(D.onDisk(held, '/c/w342', ['b.jpg', 'x.123.part', 'bad name.jpg', 'c.png']), { '/a.jpg': '/c/w342/a.jpg', '/b.jpg': '/c/w342/b.jpg', '/c.png': '/c/w342/c.png' });
  assert.deepEqual(held, { '/a.jpg': '/c/w342/a.jpg' });
  assert.deepEqual(D.onDisk(held, '', ['b.jpg']), held);
});

test('a wheel notch down moves a list 60 px on, and up moves it back', () => {
  assert.equal(D.wheeled(0, -120, 1000, 400), 60);
  assert.equal(D.wheeled(60, 120, 1000, 400), 0);
  assert.equal(D.wheeled(0, -360, 1000, 400), 180);
});

test('a touchpad\'s small angles move a list in proportion', () => {
  assert.equal(D.wheeled(100, -36, 1000, 400), 118);
});

test('the wheel stops a list at its first and last rows, and a list that fits never moves', () => {
  assert.equal(D.wheeled(0, 120, 1000, 400), 0);
  assert.equal(D.wheeled(580, -120, 1000, 400), 600);
  assert.equal(D.wheeled(600, -1200, 1000, 400), 600);
  assert.equal(D.wheeled(0, -120, 300, 400), 0);
});
