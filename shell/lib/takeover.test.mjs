import { test } from 'node:test';
import assert from 'node:assert/strict';
import { push, drop, holder, under, holds, chipText } from './takeover.mjs';

test('a prompt over the launcher draws the prompt, keeps the launcher under it and returns to it', () => {
  const stack = push([], 'polkit');
  assert.equal(holder('launcher', stack), 'polkit');
  assert.equal(under('launcher', stack), 'launcher');
  assert.equal(holder('launcher', drop(stack, 'polkit')), 'launcher');
});

test('a prompt over the resting island has nothing under it and leaves the island at rest', () => {
  const stack = push([], 'polkit');
  assert.equal(holder(null, stack), 'polkit');
  assert.equal(under(null, stack), null);
  assert.equal(holder(null, drop(stack, 'polkit')), null);
});

test('gpg then polkit over Pass: each returns to the one before, ending on Pass', () => {
  let stack = push(push([], 'pinentry'), 'polkit');
  assert.equal(holder('pass', stack), 'polkit');
  assert.equal(under('pass', stack), 'pinentry');
  stack = drop(stack, 'polkit');
  assert.equal(holder('pass', stack), 'pinentry');
  assert.equal(under('pass', stack), 'pass');
  stack = drop(stack, 'pinentry');
  assert.equal(holder('pass', stack), 'pass');
});

test('a prompt under another that hangs up leaves the top one showing, now over the surface', () => {
  const stack = drop(push(push([], 'pinentry'), 'polkit'), 'pinentry');
  assert.equal(holder('pass', stack), 'polkit');
  assert.equal(under('pass', stack), 'pass');
});

test('a prompt that shows again moves to the top once, never twice in the stack', () => {
  assert.deepEqual(push(push(push([], 'pinentry'), 'polkit'), 'pinentry'), ['polkit', 'pinentry']);
});

test('dropping a prompt that is not in the stack changes nothing', () => {
  assert.deepEqual(drop(['polkit'], 'picker'), ['polkit']);
});

test('a notification arriving under a prompt waits, at rest too, and shows once nothing holds the island', () => {
  assert.equal(holds(null, ['polkit']), true);
  assert.equal(holds('launcher', ['polkit']), true);
  assert.equal(holds('launcher', []), true);
  assert.equal(holds(null, []), false);
});

test('the chip names the surface or prompt under it in plain words, and is empty at rest', () => {
  assert.equal(chipText('launcher'), 'Launcher');
  assert.equal(chipText('notifs'), 'Notifications');
  assert.equal(chipText('cheatsheet'), 'Keys');
  assert.equal(chipText('dns'), 'DNS Shield');
  assert.equal(chipText('pinentry'), 'GPG');
  assert.equal(chipText('picker'), 'Files');
  assert.equal(chipText(null), '');
});
