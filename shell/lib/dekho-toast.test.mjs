import { test } from 'node:test';
import assert from 'node:assert/strict';
import * as B from './dekho-browse.mjs';
import { filterToast, FILTERS_CLEARED } from './dekho-toast.mjs';

const none = B.empty();
const tables = { genres: { movie: [{ name: 'Drama' }, { name: 'Horror' }], tv: [] }, languages: [] };

test('a genre chosen reads Filter: and the value as the facet box writes it', () => {
  assert.equal(filterToast({ ...none, genre: 'Horror' }, 'genre'), 'Filter: Horror');
});

test('each facet reads its own value', () => {
  assert.equal(filterToast({ ...none, kind: 'tv' }, 'kind'), 'Filter: Series');
  assert.equal(filterToast({ ...none, sort: 'top-rated' }, 'sort'), 'Filter: Top rated');
  assert.equal(filterToast({ ...none, language: { code: 'sv', name: 'Swedish' } }, 'language'), 'Filter: Swedish');
  assert.equal(filterToast({ ...none, decade: 1990 }, 'decade'), 'Filter: 1990s');
  assert.equal(filterToast({ ...none, rating: 7 }, 'rating'), 'Filter: 7+');
});

test('a person chosen reads their name on one line', () => {
  assert.equal(filterToast(B.withPerson(none, { id: 1, name: 'Lena\nHart' }), 'person'), 'Filter: Lena Hart');
});

test('a facet back at Any reads any and the facet in lower case', () => {
  assert.equal(filterToast(none, 'genre'), 'Filter: any genre');
  assert.equal(filterToast(none, 'language'), 'Filter: any language');
  assert.equal(filterToast(none, 'decade'), 'Filter: any decade');
  assert.equal(filterToast(none, 'rating'), 'Filter: any rating');
});

test('stepping a genre past the last reads any genre', () => {
  const drama = B.next(none, 'genre', tables);
  const horror = B.next(drama, 'genre', tables);
  assert.equal(filterToast(horror, 'genre'), 'Filter: Horror');
  assert.equal(filterToast(B.next(horror, 'genre', tables), 'genre'), 'Filter: any genre');
});

test('x clears with its own words', () => {
  assert.equal(FILTERS_CLEARED, 'Filters cleared');
});
