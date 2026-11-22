// dots-clip against the real cliphist on a scratch state dir.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';

const bin = new URL('../../bin/', import.meta.url).pathname;

function scratch() {
  const state = mkdtempSync(join(tmpdir(), 'dots-clip-pin-'));
  const env = { ...process.env, XDG_STATE_HOME: state };
  delete env.CLIPBOARD_STATE;
  const run = (cmd, args, input) => spawnSync(join(bin, cmd), args, { env, input, encoding: 'utf8' });
  const copy = (text) => assert.equal(run('dots-clip-store', [], text).status, 0);
  const list = () => run('dots-clip', ['list']).stdout.split('\n').filter((l) => l).map((l) => l.split('\t'));
  return { state, run, copy, list };
}

test('list is empty before the first copy, and then newest first', () => {
  const r = scratch();
  assert.deepEqual(r.list(), []);
  r.copy('one');
  r.copy('two');
  assert.deepEqual(r.list().map((l) => l[1]), ['two', 'one']);
});

test('a pinned clip lists first, on one line, and outlives its clip', () => {
  const r = scratch();
  r.copy('first line\nsecond line');
  r.copy('later');
  const id = r.list().find((l) => l[1].startsWith('first line'))[0];
  assert.equal(r.run('dots-clip', ['pin', id]).status, 0);
  const pinned = r.list()[0];
  assert.match(pinned[0], /^pin:\d+$/);
  assert.equal(pinned[1], 'first line second line');
  assert.equal(r.run('dots-clip', ['delete', id]).status, 0);
  assert.deepEqual(r.list().map((l) => l[1]), ['first line second line', 'later']);
  assert.equal(readFileSync(join(r.state, 'dots/clip-pins', pinned[0].slice(4)), 'utf8'), 'first line\nsecond line');
});

test('delete removes one clip and its time, and a pin by its name', () => {
  const r = scratch();
  r.copy('keep');
  r.copy('drop');
  const id = r.list()[0][0];
  assert.match(readFileSync(join(r.state, 'dots/clip-times'), 'utf8'), new RegExp(`^${id} `, 'm'));
  assert.equal(r.run('dots-clip', ['delete', id]).status, 0);
  assert.deepEqual(r.list().map((l) => l[1]), ['keep']);
  assert.doesNotMatch(readFileSync(join(r.state, 'dots/clip-times'), 'utf8'), new RegExp(`^${id} `, 'm'));
  r.run('dots-clip', ['pin', r.list()[0][0]]);
  const pin = r.list()[0][0];
  assert.equal(r.run('dots-clip', ['delete', pin]).status, 0);
  assert.deepEqual(readdirSync(join(r.state, 'dots/clip-pins')), []);
});

test('an id or pin name that is not digits is refused and touches no file', () => {
  const r = scratch();
  r.copy('x');
  writeFileSync(join(r.state, 'victim'), 'v');
  for (const args of [['pin', '1; rm -rf /'], ['unpin', '../victim'], ['delete', 'pin:../victim'], ['delete', 'x y'], ['nope']]) assert.equal(r.run('dots-clip', args).status, 2, args.join(' '));
  assert.equal(readFileSync(join(r.state, 'victim'), 'utf8'), 'v');
});
