// dots forget takes a line out of fish history and records it, by hash alone, as forgotten.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { forget, machine, world } from './lib.mjs';

const live = (m) => join(m.env.XDG_DATA_HOME, 'fish/fish_history');
const list = (m) => join(m.env.XDG_DATA_HOME, 'dots/fish/forgotten');
const block = (cmd, when) => `- cmd: ${cmd}\n  when: ${when}\n`;
const hash = (cmd, when) => createHash('sha256').update(Buffer.from(cmd + '\0' + when, 'latin1')).digest('hex');

function seed(m, text) {
  mkdirSync(join(m.env.XDG_DATA_HOME, 'fish'), { recursive: true });
  writeFileSync(live(m), text, 'latin1');
}

test('dots forget TOKEN123 takes out the two lines holding it, leaves the third byte for byte and records only their hashes', async () => {
  const a = machine(world(), 'a');
  const keep = '- cmd: ls -la\n  when: 1760000001\n  paths:\n    - -la\n';
  seed(a, block('echo TOKEN123', 1760000000) + keep + block('curl -H "x: TOKEN123"', 1760000002));
  const r = await forget(a, ['TOKEN123']);
  assert.equal(r.code, 0, r.stderr);
  assert.equal(r.stdout.split('\n')[0], 'forgot 2 lines');
  assert.match(r.stdout.split('\n')[1], /rotate/, 'one line says a typed secret is still to be rotated');
  assert.equal(readFileSync(live(a), 'latin1'), keep);
  const recorded = readFileSync(list(a), 'latin1');
  assert.doesNotMatch(recorded, /TOKEN123/);
  assert.deepEqual(recorded.split('\n').filter(Boolean).sort(), [hash('echo TOKEN123', 1760000000), hash('curl -H "x: TOKEN123"', 1760000002)].sort());
});

test('dots forget with text no line holds prints forgot 0 lines, exits 0 and leaves the history byte for byte', async () => {
  const a = machine(world(), 'a');
  const text = block('echo one', 1760000000) + block('echo two', 1760000001);
  seed(a, text);
  const r = await forget(a, ['nothing-matches']);
  assert.equal(r.code, 0, r.stderr);
  assert.equal(r.stdout, 'forgot 0 lines\n');
  assert.equal(readFileSync(live(a), 'latin1'), text);
});

test('dots forget with no text exits 2 with its usage line, and empty text forgets nothing', async () => {
  const a = machine(world(), 'a');
  const text = block('echo one', 1760000000);
  seed(a, text);
  const none = await forget(a, []);
  assert.equal(none.code, 2);
  assert.match(none.stderr, /^usage: dots forget <text>$/m);
  const empty = await forget(a, ['']);
  assert.equal(empty.code, 0, empty.stderr);
  assert.equal(empty.stdout, 'forgot 0 lines\n');
  assert.equal(readFileSync(live(a), 'latin1'), text);
  assert.ok(!existsSync(list(a)) || readFileSync(list(a), 'latin1') === '', 'no line was recorded');
});

test('dots forget matches its text as plain text: a quote, a dot, a backslash, a newline and Bangla', async () => {
  const a = machine(world(), 'a');
  // fish writes a backslash as \\ and a newline as \n inside cmd, and the rest as UTF-8.
  const bangla = Buffer.from('echo ঢাকা', 'utf8').toString('latin1');
  const lines = {
    quote: block(`echo "it's"`, 1760000000),
    dot: block('echo a.b', 1760000001),
    nodot: block('echo axb', 1760000002),
    backslash: block('echo a\\\\b', 1760000003),
    newline: block('printf one\\ntwo', 1760000004),
    bangla: block(bangla, 1760000005),
  };
  seed(a, Object.values(lines).join(''));
  for (const [text, gone] of [[`"it's"`, 'quote'], ['a.b', 'dot'], ['a\\b', 'backslash'], ['one\ntwo', 'newline'], ['ঢাকা', 'bangla']]) {
    const r = await forget(a, [text]);
    assert.equal(r.stdout.split('\n')[0], 'forgot 1 line', `${JSON.stringify(text)}: ${r.stdout}${r.stderr}`);
    delete lines[gone];
    assert.equal(readFileSync(live(a), 'latin1'), Object.values(lines).join(''), `${JSON.stringify(text)} took out only its own line`);
  }
});
