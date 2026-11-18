import { test } from 'node:test';
import assert from 'node:assert/strict';
import { IMAGE_MAX, TEXT_MAX, VISION_MODEL, check, chipText, content, isImage, modelFor, pillText, sizeText } from './chat-files.mjs';

const KiB = 1024;
const MiB = 1024 * 1024;

test('limits', () => {
  assert.equal(TEXT_MAX, 512 * KiB);
  assert.equal(IMAGE_MAX, 5 * MiB);
});

test('isImage goes by extension, any case', () => {
  for (const n of ['a.png', 'a.JPG', 'a.jpeg', 'a.gif', 'a.WebP']) assert.equal(isImage(n), true, n);
  for (const n of ['a.txt', 'png', 'a.png.txt', 'a.svg']) assert.equal(isImage(n), false, n);
});

test('check names the limit when a file is over it', () => {
  assert.equal(check({ name: 'notes.txt', kind: 'text', size: 600 * KiB }), 'notes.txt is 600 KiB, over the 512 KiB limit');
  assert.equal(check({ name: 'shot.png', kind: 'image', size: 6 * MiB }), 'shot.png is 6 MiB, over the 5 MiB limit');
  assert.equal(check({ name: 'notes.txt', kind: 'text', size: 512 * KiB }), null);
  assert.equal(check({ name: 'shot.png', kind: 'image', size: 5 * MiB }), null);
  assert.match(check({ name: 'notes.txt', kind: 'text', size: 512 * KiB + 1 }), /512 KiB/);
});

test('sizeText', () => {
  assert.equal(sizeText(0), '0 KiB');
  assert.equal(sizeText(1), '1 KiB');
  assert.equal(sizeText(1023), '1 KiB');
  assert.equal(sizeText(2048), '2 KiB');
  assert.equal(sizeText(1.5 * MiB), '1.5 MiB');
  assert.equal(sizeText(6 * MiB), '6 MiB');
});

test('chipText', () => {
  assert.equal(chipText({ name: 'notes.txt', size: 2048 }), 'notes.txt · 2 KiB');
});

test('an image attachment switches the model to vision', () => {
  assert.equal(VISION_MODEL, 'amd/DeepSeek-V4-Flash-Vision-Exp');
  const img = { name: 'a.png', kind: 'image', data: 'data:image/png;base64,AAAA' };
  const txt = { name: 'a.txt', kind: 'text', text: 'hi' };
  assert.equal(modelFor('fast', []), 'fast');
  assert.equal(modelFor('fast', [txt]), 'fast');
  assert.equal(modelFor('fast', [txt, img]), VISION_MODEL);
  assert.equal(pillText('fast', [txt]), 'fast');
  assert.equal(pillText('fast', [img]), 'vision · amd/DeepSeek-V4-Flash-Vision-Exp');
});

test('content is a string without images and parts with them', () => {
  const txt = { name: 'a.txt', kind: 'text', text: 'hello' };
  const img = { name: 'a.png', kind: 'image', data: 'data:image/png;base64,AAAA' };
  assert.equal(content('hi', []), 'hi');
  assert.equal(content('hi', [txt]), 'hi\n\n```a.txt\nhello\n```');
  assert.deepEqual(content('hi', [txt, img]), [
    { type: 'text', text: 'hi\n\n```a.txt\nhello\n```' },
    { type: 'image_url', image_url: { url: 'data:image/png;base64,AAAA' } },
  ]);
});
