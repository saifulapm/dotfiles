// The desktop skill and its two operators name only v2's commands and the shell's real IPC targets, and scripts/screen types nothing while the session is locked.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { chmodSync, existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const repo = new URL('../../', import.meta.url).pathname;
const skill = join(repo, 'home/dot_claude/skills/desktop');
const screen = join(skill, 'scripts/screen');
const files = [
  join(skill, 'SKILL.md'),
  ...readdirSync(join(skill, 'scripts')).map((f) => join(skill, 'scripts', f)),
  join(repo, 'home/dot_claude/agents/desktop-operator.md'),
  join(repo, 'home/dot_claude/agents/browser-operator.md'),
];
const text = (f) => readFileSync(f, 'utf8');

test('no file of the skill or its operators names a v1 command', () => {
  const hits = files.flatMap((f) => text(f).split('\n').filter((l) => /foot-run|app-run|launch-or-focus|theme-set|qshell|lock status/.test(l)).map((l) => `${f}: ${l}`));
  assert.deepEqual(hits, []);
});

// The shell's targets, read from its QML now; services/Media.qml holds media, so the walk goes into subfolders.
function targets() {
  const qml = readdirSync(join(repo, 'shell'), { recursive: true }).filter((f) => f.endsWith('.qml'));
  return new Set(qml.flatMap((f) => [...text(join(repo, 'shell', f)).matchAll(/\btarget: "(\w+)"/g)].map((m) => m[1])));
}

test('every IPC target the skill names is one the shell defines', () => {
  const known = targets();
  assert.ok(known.has('lock') && known.has('media'), [...known].join());
  const named = new Set();
  for (const f of files) for (const m of text(f).matchAll(/\b(?:dots-call|qs ipc call)\s+(\w+)/g)) named.add(m[1]);
  // The skill's IPC table puts each target in the first cell, in backticks.
  const table = [...text(join(skill, 'SKILL.md')).matchAll(/^\| `(\w+)` \|/gm)].map((m) => m[1]);
  assert.ok(table.length > 0, 'the skill has no IPC table');
  for (const t of table) named.add(t);
  assert.deepEqual([...named].filter((n) => !known.has(n)), []);
});

// A PATH whose dots-call answers lock state with the given JSON (or, given a function, runs its body), whose dots-call and input tools log their argv to one file, in call order, and whose niri says a plain app has focus; XDG_STATE_HOME is the same scratch dir.
function stubs(lockState, inputExit) {
  const dir = mkdtempSync(join(tmpdir(), 'desktop-skill-'));
  const log = join(dir, 'calls.log');
  const put = (name, body) => {
    writeFileSync(join(dir, name), `#!/usr/bin/env bash\n${body}\n`);
    chmodSync(join(dir, name), 0o755);
  };
  const answer = typeof lockState === 'function' ? lockState() : `echo '${lockState}'; exit 0`;
  put('dots-call', `echo "dots-call $*" >>'${log}'; [[ "$*" == "lock state" ]] && { ${answer}; }; exit 1`);
  put('qs', 'echo "Function not found" >&2; exit 1');
  put('niri', `echo '{"app_id":"org.gnome.TextEditor"}'`);
  for (const t of ['wtype', 'ydotool', 'wlrctl', 'dots-pointer', 'grim']) put(t, `echo "${t} $*" >>'${log}'; exit ${inputExit}`);
  // The journal and the desk state go to the scratch dir, never the live ~/.local/state or runtime dir.
  return { env: { ...process.env, PATH: `${dir}:${process.env.PATH}`, XDG_STATE_HOME: dir, XDG_RUNTIME_DIR: dir }, log, journal: join(dir, 'dots/agent-journal.ndjson') };
}

const locked = '{"locked":true,"secure":true}';
const scripts = join(skill, 'scripts');
const inputs = [
  ['screen', 'type', 'hi'], ['screen', 'type', 'hi', '--any'], ['screen', 'key', 'Return'], ['screen', 'click', '1', '1'],
  ['screen', 'click', '1', '1', 'left', '1', '--any'], ['screen', 'drag', '1', '1', '2', '2'], ['screen', 'move', '1', '1'], ['screen', 'scroll', '1', '1', 'down'],
  ['mouse', 'click', '10', '10'], ['mouse', 'click', '10', '10', 'left', '1', '--any'], ['mouse', 'to', '10', '10'], ['mouse', 'drag', '1', '1', '2', '2'], ['mouse', 'scroll', '1', '1', 'down'],
  ['gui', 'click', 'files', 'Save'], ['gui', 'click', 'files', 'Save', '--any'], ['gui', 'type', 'files', 'Name', 'x'],
];

// Keys or a press at a lock land in its password field, so every input path reads the lock first and refuses with exit 3.
for (const [tool, ...args] of inputs) {
  test(`${tool} ${args.join(' ')} refuses while the session is locked and sends no input`, () => {
    const { env, log } = stubs(locked, 1);
    const r = spawnSync(join(scripts, tool), args, { env, encoding: 'utf8' });
    assert.equal(r.status, 3, r.stderr);
    assert.deepEqual(JSON.parse(r.stdout), { refused: 'locked' });
    assert.equal(existsSync(log) ? readFileSync(log, 'utf8') : '', 'dots-call lock state\n');
  });
}

// Anything but a literal "locked": false counts as locked: a lock state that fails, says nothing, or says it another way.
for (const [why, answer] of [['fails', () => 'exit 1'], ['prints nothing', () => 'exit 0'], ['says "false" as a string', '{"locked":"false"}']]) {
  for (const tool of [['mouse', 'click', '10', '10'], ['gui', 'click', 'files', 'Save'], ['screen', 'type', 'hi', '--any']]) {
    test(`${tool.join(' ')} counts a lock state that ${why} as locked`, () => {
      const { env, log } = stubs(answer, 1);
      const r = spawnSync(join(scripts, tool[0]), tool.slice(1), { env, encoding: 'utf8' });
      assert.equal(r.status, 3, r.stderr);
      assert.deepEqual(JSON.parse(r.stdout), { refused: 'locked' });
      assert.equal(readFileSync(log, 'utf8'), 'dots-call lock state\n');
    });
  }
}

// --any skips the agent-window check, which needs a niri; tests/dev/desk-keys.sh checks it.
test('screen type --any gets past the guard once lock state reads unlocked', () => {
  const { env, log } = stubs('{"locked":false,"secure":true,"heldBy":"claude","unlockedAt":1,"leaseUntil":2}', 0);
  const r = spawnSync(screen, ['type', 'hi', '--any'], { env, encoding: 'utf8' });
  assert.equal(r.status, 0, r.stderr);
  assert.equal(readFileSync(log, 'utf8'), 'dots-call lock state\nwtype -- hi\n');
});

// dots-pointer is the skill's pointer, built at apply from wlr-protocols' XML like dots-dshift, and rebuilt when its source changes.
test('apply builds dots-pointer from bin/dots-pointer.c and the virtual-pointer XML', () => {
  const script = text(join(repo, 'home/.chezmoiscripts/run_onchange_after_13-pointer.sh.tmpl'));
  assert.match(script, /^# pointer source hash: \{\{ joinPath \.chezmoi\.workingTree "bin\/dots-pointer\.c" \| include \| sha256sum \}\}$/m);
  assert.match(script, /^xml=\/usr\/share\/wlr-protocols\/unstable\/wlr-virtual-pointer-unstable-v1\.xml$/m);
  assert.match(script, /wayland-scanner client-header "\$xml"/);
  assert.match(script, /wayland-scanner private-code "\$xml"/);
  assert.match(script, /gcc -O2 -Wall .*-o "\$HOME\/\.local\/bin\/dots-pointer" .*bin\/dots-pointer\.c.* -lwayland-client \|\| \{/);
});

const unlocked = '{"locked":false,"secure":true,"heldBy":"claude","unlockedAt":1,"leaseUntil":2}';
const lines = (f) => readFileSync(f, 'utf8').trim().split('\n').map((l) => JSON.parse(l));

// Each action is one journal line, and typed text is kept as its length and digest, never as the text.
test('screen type leaves one journal line with the text as length and sha256', () => {
  const { env, journal } = stubs(unlocked, 0);
  const r = spawnSync(join(scripts, 'screen'), ['type', 'hello', '--any'], { env, encoding: 'utf8' });
  assert.equal(r.status, 0, r.stderr);
  const [line, ...more] = lines(journal);
  assert.deepEqual(more, []);
  assert.equal(line.tool, 'screen');
  assert.equal(line.outcome, 'ok');
  assert.deepEqual(line.args[0], 'type');
  assert.equal(line.args[1].len, 5);
  assert.match(line.args[1].sha256, /^[0-9a-f]{64}$/);
  assert.equal(line.window.app_id, 'org.gnome.TextEditor');
  assert.ok(Number.isInteger(line.ms) && line.ms >= 0, `ms ${line.ms}`);
  assert.ok(!Number.isNaN(Date.parse(line.ts)), line.ts);
  assert.doesNotMatch(readFileSync(journal, 'utf8'), /hello/);
});

test('a refusal is a journal line too, naming the window it saw', () => {
  const { env, journal } = stubs(locked, 1);
  spawnSync(join(scripts, 'gui'), ['type', 'files', 'Name', 'secret-value'], { env, encoding: 'utf8' });
  spawnSync(join(scripts, 'mouse'), ['click', '10', '10'], { env, encoding: 'utf8' });
  const [gui, mouse] = lines(journal);
  assert.equal(gui.tool, 'gui');
  assert.equal(gui.outcome, 'refused');
  assert.equal(gui.args[3].len, 'secret-value'.length);
  assert.equal(mouse.tool, 'mouse');
  assert.equal(mouse.outcome, 'refused');
  assert.deepEqual(mouse.args, ['click', '10', '10']);
  assert.equal(mouse.window.app_id, 'org.gnome.TextEditor');
  assert.doesNotMatch(readFileSync(journal, 'utf8'), /secret-value/);
});

test('a usage error is no action and leaves no journal line', () => {
  const { env, journal } = stubs(unlocked, 0);
  assert.equal(spawnSync(join(scripts, 'mouse'), ['click', '10'], { env: { ...env, MOUSE_SCREEN: '100x100' }, encoding: 'utf8' }).status, 2);
  assert.equal(spawnSync(join(scripts, 'screen'), ['key'], { env, encoding: 'utf8' }).status, 2);
  assert.ok(!existsSync(journal));
});

// The day's first line prunes the lines older than 30 days.
test('the first journal line of a day drops lines older than 30 days and keeps the rest', () => {
  const { env, journal } = stubs(locked, 1);
  const ago = (days) => new Date(Date.now() - days * 86400000).toISOString();
  mkdirSync(join(journal, '..'), { recursive: true });
  writeFileSync(journal, [31, 29].map((d) => JSON.stringify({ ts: ago(d), tool: 'screen', args: [`day${d}`], outcome: 'ok', ms: 1, window: null })).join('\n') + '\n');
  spawnSync(join(scripts, 'mouse'), ['click', '10', '10'], { env, encoding: 'utf8' });
  const kept = lines(journal);
  assert.deepEqual(kept.map((l) => l.args[0]), ['day29', 'click']);
  // The day's second write prunes nothing more.
  spawnSync(join(scripts, 'mouse'), ['click', '10', '10'], { env, encoding: 'utf8' });
  assert.deepEqual(lines(journal).map((l) => l.args[0]), ['day29', 'click', 'click']);
});

// gui takes --any only as its last argument, so text after a misplaced one is still kept as length and digest.
test('gui type keeps every argument from its text on out of the journal', () => {
  const { env, journal } = stubs(locked, 1);
  spawnSync(join(scripts, 'gui'), ['type', 'files', 'Name', '--any', 'secret-value'], { env, encoding: 'utf8' });
  const [line] = lines(journal);
  assert.deepEqual(line.args.slice(0, 3), ['type', 'files', 'Name']);
  assert.equal(line.args[4].len, 'secret-value'.length);
  assert.doesNotMatch(readFileSync(journal, 'utf8'), /secret-value/);
});

// Two outputs side by side, the focused one on the left, so the rightmost is never the one meant.
function twoOutputs() {
  const s = stubs(unlocked, 1);
  const dir = join(s.log, '..');
  const out = (name, x, width, height, scale) => ({ name, logical: { x, y: 0, width, height, scale, transform: 'Normal' } });
  const outputs = { 'DP-1': out('DP-1', 0, 1920, 1080, 1), 'eDP-1': out('eDP-1', 1920, 2048, 1280, 1.25) };
  writeFileSync(join(dir, 'niri'), `#!/usr/bin/env bash
case "$*" in
"msg -j outputs") echo '${JSON.stringify(outputs)}' ;;
"msg -j focused-output") echo '${JSON.stringify(outputs['DP-1'])}' ;;
*) echo '{"app_id":"org.gnome.TextEditor"}' ;;
esac
`);
  return { ...s, env: { ...s.env, NIRI_SOCKET: join(dir, 'niri.sock') } };
}

// grim fails in the stub, so no test writes /tmp/desk/shot.png; the call it got is what counts.
test('screen shot covers the focused output, not the rightmost', () => {
  const { env, log } = twoOutputs();
  spawnSync(screen, ['shot'], { env, encoding: 'utf8' });
  assert.match(readFileSync(log, 'utf8'), /^grim -g 0,0 1920x1080 -s 0\.666667 /m);
});

test('screen shot --output names another output', () => {
  const { env, log } = twoOutputs();
  spawnSync(screen, ['shot', '--output', 'eDP-1'], { env, encoding: 'utf8' });
  assert.match(readFileSync(log, 'utf8'), /^grim -g 1920,0 2048x1280 -s 0\.625 /m);
});

test('screen shot --output with no such output exits 2 naming the outputs there are', () => {
  const { env, log } = twoOutputs();
  const r = spawnSync(screen, ['shot', '--output', 'nope'], { env, encoding: 'utf8' });
  assert.equal(r.status, 2);
  assert.match(r.stderr, /nope.*DP-1, eDP-1/);
  assert.ok(!existsSync(log) || !/grim/.test(readFileSync(log, 'utf8')));
});

// A point on the left output stays where it is; only the edges of the output under it clamp it.
test('mouse keeps a point inside the output under it', () => {
  const { env, log } = twoOutputs();
  const r = spawnSync(join(scripts, 'mouse'), ['to', '100', '0'], { env, encoding: 'utf8' });
  assert.equal(r.status, 1, r.stderr);
  assert.match(readFileSync(log, 'utf8'), /^dots-pointer 0,0,3968,1280 move 100 2$/m);
});
