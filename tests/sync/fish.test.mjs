// Fish history travels as one <machine>.history file per machine and merges into each live history.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { fishHistory, machine, sync, world } from './lib.mjs';

const live = (m) => join(m.env.XDG_DATA_HOME, 'fish/fish_history');
const blocks = (m, cmd) => readFileSync(live(m), 'utf8').split('\n').filter((l) => l === '- cmd: ' + cmd).length;

async function ok(m) {
  const r = await sync(m);
  assert.equal(r.code, 0, `dots sync on ${m.id} exited ${r.code}: ${r.stdout}${r.stderr}`);
}

test("a command in a's fish history shows once in b's history, and a third round adds no duplicate", async () => {
  const w = world();
  const [a, b] = [machine(w, 'a'), machine(w, 'b')];
  mkdirSync(join(a.env.XDG_DATA_HOME, 'fish'), { recursive: true });
  writeFileSync(live(a), '- cmd: echo only-on-a\n  when: 1760000000\n');
  mkdirSync(join(b.env.XDG_DATA_HOME, 'fish'), { recursive: true });
  writeFileSync(live(b), '- cmd: ls\n  when: 1760000005\n');
  await ok(a);
  await ok(b);
  const shown = (await fishHistory(b)).stdout.split('\n');
  assert.deepEqual(shown.filter((l) => l === 'echo only-on-a'), ['echo only-on-a']);
  assert.equal(blocks(b, 'echo only-on-a'), 1);
  await ok(a);
  await ok(b);
  await ok(a);
  assert.equal(blocks(b, 'echo only-on-a'), 1);
  assert.equal(blocks(a, 'echo only-on-a'), 1);
  assert.equal(blocks(a, 'ls'), 1);
});
