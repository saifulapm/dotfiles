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
