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

test("mpv has mapped once niri lists a window with mpv's app id whose process is in the film's unit", () => {
  const both = '[{"id":3,"app_id":"dekho","pid":10},{"id":7,"app_id":"mpv","pid":71},{"id":9,"app_id":"mpv","pid":92}]';
  assert.equal(S.mpvMapped(both, [90, 92]), true);
  assert.equal(S.mpvMapped('[{"id":3,"app_id":"dekho","pid":10},{"id":7,"app_id":"mpv","pid":71}]', [90, 92]), false);
  assert.equal(S.mpvMapped(both, []), false);
  assert.equal(S.mpvMapped('[{"id":3,"app_id":"dekho","pid":92}]', [92]), false);
  assert.equal(S.mpvMapped('', [92]), false);
  assert.equal(S.mpvMapped('{"Err":"no niri"}', [92]), false);
});
