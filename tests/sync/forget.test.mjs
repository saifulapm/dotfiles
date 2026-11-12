// dots forget takes a line out of fish history and records it, by hash alone, as forgotten.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { appendFileSync, existsSync, mkdirSync, readdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { forget, holdLock, machine, sync, world } from './lib.mjs';

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
  assert.match(none.stderr, /^usage: dots forget \[--\] <text>$/m);
  const empty = await forget(a, ['']);
  assert.equal(empty.code, 0, empty.stderr);
  assert.equal(empty.stdout, 'forgot 0 lines\n');
  assert.equal(readFileSync(live(a), 'latin1'), text);
  assert.ok(!existsSync(list(a)) || readFileSync(list(a), 'latin1') === '', 'no line was recorded');
});

test('dots forget refuses a text that looks like a flag, and forgets one after --', async () => {
  const a = machine(world(), 'a');
  const text = block('ls --help', 1760000000) + block('du -h', 1760000001) + block('curl --token=abc', 1760000002);
  seed(a, text);
  for (const args of [['--help'], ['-h'], ['--token=abc']]) {
    const r = await forget(a, args);
    assert.equal(r.code, 2, args.join(' '));
    assert.match(r.stderr, /^usage: dots forget \[--\] <text>$/m);
    assert.equal(readFileSync(live(a), 'latin1'), text, `${args.join(' ')} forgot nothing`);
  }
  const r = await forget(a, ['--', '--token=abc']);
  assert.equal(r.stdout.split('\n')[0], 'forgot 1 line', r.stderr);
  assert.equal(readFileSync(live(a), 'latin1'), block('ls --help', 1760000000) + block('du -h', 1760000001));
});

test('dots forget says the fish sessions open now still hold the line', async () => {
  const a = machine(world(), 'a');
  seed(a, block('echo TOKEN123', 1760000000));
  const r = await forget(a, ['TOKEN123']);
  assert.match(r.stdout, /open fish sessions/);
  assert.equal(r.stdout.split('\n').filter(Boolean).length, 2, 'the count and one line');
});

test('dots forget waits for a sync round holding the lock, so the round cannot write its list over the new hashes', async () => {
  const a = machine(world(), 'a');
  seed(a, block('echo TOKEN123', 1760000000));
  const held = await holdLock(a, 1.5);
  const t0 = Date.now();
  const r = await forget(a, ['TOKEN123']);
  assert.equal(r.stdout.split('\n')[0], 'forgot 1 line', r.stderr);
  assert.ok(Date.now() - t0 >= 1000, `forget returned after ${Date.now() - t0} ms, before the lock was let go`);
  await held.freed;
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

async function ok(m) {
  const r = await sync(m, ['--only', 'fish']);
  assert.equal(r.code, 0, `dots sync on ${m.id} exited ${r.code}: ${r.stdout}${r.stderr}`);
}
const holds = (m, text) => existsSync(live(m)) && readFileSync(live(m), 'latin1').includes(text);
// Every *.history file on the remote whose text holds text, by name.
const remoteHolding = (w, text) =>
  readdirSync(join(w.remote, 'dots-sync/fish')).filter((f) => f.endsWith('.history') && readFileSync(join(w.remote, 'dots-sync/fish', f), 'latin1').includes(text));

// a and b both hold the TOKEN123 line and one other, after a round each.
async function shared(w) {
  const [a, b] = [machine(w, 'a'), machine(w, 'b')];
  seed(a, block('echo TOKEN123', 1760000000) + block('echo from-a', 1760000001));
  seed(b, block('echo from-b', 1760000002));
  await ok(a);
  await ok(b);
  assert.ok(holds(b, 'TOKEN123'), 'b pulled the line before the forget');
  return [a, b];
}

test('a line a forgets is gone from both live histories and every remote history after a round on a, b and a again', async () => {
  const w = world();
  const [a, b] = await shared(w);
  assert.equal((await forget(a, ['TOKEN123'])).stdout.split('\n')[0], 'forgot 1 line');
  await ok(a);
  await ok(b);
  await ok(a);
  assert.ok(!holds(a, 'TOKEN123'), 'a');
  assert.ok(!holds(b, 'TOKEN123'), 'b');
  assert.deepEqual(remoteHolding(w, 'TOKEN123'), []);
  assert.ok(existsSync(join(w.remote, 'dots-sync/fish/a.forgotten')), "a's list went up beside its history");
  for (const m of [a, b]) for (const other of ['from-a', 'from-b']) assert.ok(holds(m, other), `${m.id} keeps ${other}`);
});

test('a line b adds after a forgets, and the same command typed again later, are kept on both', async () => {
  const w = world();
  const [a, b] = await shared(w);
  await forget(a, ['TOKEN123']);
  appendFileSync(live(b), block('echo after-the-forget', 1760000100) + block('echo TOKEN123', 1760000101));
  await ok(a);
  await ok(b);
  await ok(a);
  for (const m of [a, b]) {
    const text = readFileSync(live(m), 'latin1');
    assert.ok(text.includes(block('echo after-the-forget', 1760000100)), `${m.id} has b's new line`);
    assert.ok(text.includes(block('echo TOKEN123', 1760000101)), `${m.id} has the command typed again`);
    assert.ok(!text.includes(block('echo TOKEN123', 1760000000)), `${m.id} has not the forgotten one`);
  }
});

test('a forgotten line a fish session writes back into the live history is taken out at the next round', async () => {
  const w = world();
  const [a] = await shared(w);
  await forget(a, ['TOKEN123']);
  await ok(a);
  appendFileSync(live(a), block('echo TOKEN123', 1760000000));
  await ok(a);
  assert.ok(!holds(a, 'TOKEN123'));
  assert.ok(!remoteHolding(w, 'TOKEN123').includes('a.history'), "a's history on the remote");
});

test('a machine off since before the forget drops the line before its own next push', async () => {
  const w = world();
  const [a] = await shared(w);
  const c = machine(w, 'c');
  await ok(c);
  assert.ok(holds(c, 'TOKEN123'));
  await forget(a, ['TOKEN123']);
  await ok(a);
  await ok(c);
  assert.ok(!holds(c, 'TOKEN123'));
  assert.ok(!remoteHolding(w, 'TOKEN123').includes('c.history'), "c's first push");
});

test('a reinstall with no history and no list forgets nothing and takes its old list back', async () => {
  const w = world();
  const [a, b] = await shared(w);
  await forget(a, ['TOKEN123']);
  await ok(a);
  await ok(b);
  const old = readFileSync(list(a), 'latin1');
  rmSync(a.env.XDG_DATA_HOME, { recursive: true, force: true });
  mkdirSync(a.env.XDG_DATA_HOME);
  await ok(a);
  assert.ok(holds(a, 'from-a') && holds(a, 'from-b'), 'every line comes back');
  assert.ok(!holds(a, 'TOKEN123'));
  assert.equal(readFileSync(list(a), 'latin1'), old);
});

test('a lone machine reinstalled takes its old list back from its own file on the remote', async () => {
  const w = world();
  const a = machine(w, 'a');
  seed(a, block('echo TOKEN123', 1760000000) + block('echo kept', 1760000001));
  await ok(a);
  await forget(a, ['TOKEN123']);
  await ok(a);
  const old = readFileSync(list(a), 'latin1');
  rmSync(a.env.XDG_DATA_HOME, { recursive: true, force: true });
  mkdirSync(a.env.XDG_DATA_HOME);
  await ok(a);
  assert.equal(readFileSync(list(a), 'latin1'), old);
  assert.ok(holds(a, 'echo kept') && !holds(a, 'TOKEN123'));
});

test('two machines forgetting different lines in the same round both stay gone', async () => {
  const w = world();
  const [a, b] = await shared(w);
  await forget(a, ['TOKEN123']);
  await forget(b, ['from-b']);
  await ok(a);
  await ok(b);
  await ok(a);
  await ok(b);
  for (const m of [a, b]) {
    assert.ok(!holds(m, 'TOKEN123') && !holds(m, 'from-b'), m.id);
    assert.ok(holds(m, 'from-a'), m.id);
  }
  assert.deepEqual(remoteHolding(w, 'TOKEN123').concat(remoteHolding(w, 'from-b')), []);
});

test('a pulled list that does not parse fails the fish unit naming it, changes no history, and the other units still sync', async () => {
  const w = world();
  const [a, b] = await shared(w);
  appendFileSync(live(b), block('echo new-on-b', 1760000200));
  await ok(b);
  writeFileSync(join(w.remote, 'dots-sync/fish/b.forgotten'), 'not a hash\n');
  const text = readFileSync(live(a), 'latin1');
  const pushed = readFileSync(join(w.remote, 'dots-sync/fish/a.history'), 'latin1');
  const r = await sync(a);
  assert.notEqual(r.code, 0);
  const status = JSON.parse(readFileSync(a.status, 'utf8'));
  assert.equal(status.fish.ok, false);
  assert.match(status.fish.error, /b\.forgotten/);
  assert.equal(readFileSync(live(a), 'latin1'), text, 'the live history is as it was');
  assert.equal(readFileSync(join(w.remote, 'dots-sync/fish/a.history'), 'latin1'), pushed, "a's history on the remote is as it was");
  for (const unit of ['notes', 'goals', 'youtube', 'ssh']) assert.equal(status[unit].ok, true, `${unit}: ${status[unit].error}`);
});
