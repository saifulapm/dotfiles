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
