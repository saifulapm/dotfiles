import { test } from 'node:test';
import assert from 'node:assert/strict';
import * as S from './dekho-starting.mjs';

const buffered = [
  { text: 'Found 530 seeders', state: 'done' },
  { text: 'mpv starts at 108 MB', state: 'done' },
];

test('after playing, Starting adds a current step saying mpv is opening', () => {
  assert.deepEqual(S.steps({ steps: buffered, playing: true }), [
    { text: 'Found 530 seeders', state: 'done' },
    { text: 'mpv starts at 108 MB', state: 'done' },
    { text: 'mpv is opening', state: 'current' },
  ]);
});

test('before playing, the steps are the buffering ones alone', () => {
  const steps = [{ text: 'Found 530 seeders', state: 'current' }];
  assert.deepEqual(S.steps({ steps, playing: false }), [{ text: 'Found 530 seeders', state: 'current' }]);
});

test("mpv has mapped once niri lists a window with mpv's app id", () => {
  assert.equal(S.mpvMapped('[{"id":3,"app_id":"dekho"},{"id":9,"app_id":"mpv"}]'), true);
  assert.equal(S.mpvMapped('[{"id":3,"app_id":"dekho"}]'), false);
  assert.equal(S.mpvMapped(''), false);
  assert.equal(S.mpvMapped('{"Err":"no niri"}'), false);
});
