// The desktop skill and its two operators name only v2's commands and the shell's real IPC targets, and scripts/screen types nothing while the session is locked.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { spawn } from 'node:child_process';
import { createServer } from 'node:net';
import { chmodSync, existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, unlinkSync, writeFileSync } from 'node:fs';
import { crc32, deflateSync } from 'node:zlib';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const repo = new URL('../../', import.meta.url).pathname;
const skill = join(repo, 'home/dot_claude/skills/desktop');
const screen = join(skill, 'scripts/screen');
const files = [
  join(skill, 'SKILL.md'),
  join(skill, 'reference.md'),
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

const doc = text(join(skill, 'SKILL.md'));
const linesOf = (f) => text(f).split('\n');
const operators = ['desktop-operator', 'browser-operator'].map((n) => join(repo, `home/dot_claude/agents/${n}.md`));

test('SKILL.md stays under 20,000 characters', () => {
  assert.ok(doc.length < 20000, String(doc.length));
});

test('SKILL.md names launch, wait, doctor and --then', () => {
  for (const w of ['screen launch', 'screen wait', 'screen doctor', '--then']) assert.ok(doc.includes('`' + w) || doc.includes(w), w);
  for (const w of ['screen launch', 'screen wait', 'screen doctor']) assert.match(doc, new RegExp('`[^`\\n]*' + w), w);
});

test('SKILL.md says never to send input with wtype, wlrctl or ydotool', () => {
  assert.ok(linesOf(join(skill, 'SKILL.md')).some((l) => /never/i.test(l) && /wtype/.test(l) && /wlrctl/.test(l) && /ydotool/.test(l)));
});

test('SKILL.md runs no bare wtype in a code block, and its worked example launches through screen', () => {
  let fenced = false;
  const bare = [];
  for (const l of linesOf(join(skill, 'SKILL.md'))) {
    if (l.startsWith('```')) fenced = !fenced;
    else if (fenced && /^\s*wtype\b|&&\s*wtype\b/.test(l)) bare.push(l);
  }
  assert.deepEqual(bare, []);
  const example = doc.split('**The worked example**')[1].split('\n## ')[0];
  assert.match(example, /screen launch/);
});

// A wait for any foot answers at once for one of Saiful's, and the focused window can still be his, so the example closes only the id its own app id's wait printed.
test('the worked example closes only the window its own launch opened', () => {
  const example = doc.split('**The worked example**')[1].split('\n## ')[0];
  const app = example.match(/screen launch foot -a ([\w-]+)/)?.[1];
  assert.ok(app, 'the example launches foot under an app id of its own');
  assert.match(example, new RegExp(`id=\\$\\(\\$screen wait window-open --app ${app} \\| jq -er \\.window\\.id\\)`));
  assert.doesNotMatch(example, /focused-window/);
});

test('SKILL.md links reference.md, which holds the refusal reasons', () => {
  assert.match(doc, /\]\(reference\.md\)/);
  const ref = text(join(skill, 'reference.md'));
  for (const r of ['locked', 'auth prompt', 'not an agent window', 'no window', 'no answer', 'busy']) assert.ok(ref.includes(r), r);
});

test('desktop-operator passes --any and --jev only as the brief grants, and hands back on an auth prompt', () => {
  const l = linesOf(operators[0]);
  assert.ok(l.some((x) => /--any/.test(x) && /only/i.test(x) && /brief grants/.test(x)));
  assert.ok(l.some((x) => /--jev/.test(x) && /JEV allowed/.test(x)));
  assert.ok(l.some((x) => /exit 3/.test(x) && /auth prompt/.test(x) && /hand/i.test(x)));
});

// SKILL.md says never bare ydotool, and ydotoold's device reaches the live session even from a nested one, so the operator ends idle's dim through screen move.
test('desktop-operator names no raw input tool, and ends the dim with screen move', () => {
  const t = text(operators[0]);
  assert.doesNotMatch(t, /ydotool|wtype|wlrctl/);
  assert.match(t, /dimmed[^]*?`screen move/);
});

test('browser-operator passes --any and --jev only as the brief grants, and hands back on an auth prompt', () => {
  const l = linesOf(operators[1]);
  assert.ok(l.some((x) => /--any/.test(x) && /only/i.test(x) && /brief grants/.test(x)));
  assert.ok(l.some((x) => /--jev/.test(x) && /JEV allowed/.test(x)));
  assert.ok(l.some((x) => /exit 3/.test(x) && /auth prompt/.test(x) && /hand/i.test(x)));
});

// A PATH whose dots-call answers lock state, polkit state and pinentry state with the given JSON (or, given a function, runs its body), the prompts closed unless given, whose dots-call and input tools log their argv to one file, in call order, and whose niri says a plain app has focus; XDG_STATE_HOME is the same scratch dir.
function stubs(lockState, inputExit, { polkit = closed, pinentry = closed } = {}) {
  const dir = mkdtempSync(join(tmpdir(), 'desktop-skill-'));
  const log = join(dir, 'calls.log');
  const put = (name, body) => {
    writeFileSync(join(dir, name), `#!/usr/bin/env bash\n${body}\n`);
    chmodSync(join(dir, name), 0o755);
  };
  const say = (a) => (typeof a === 'function' ? a() : `echo '${a}'; exit 0`);
  put('dots-call', `echo "dots-call $*" >>'${log}'; case "$*" in "lock state") ${say(lockState)} ;; "polkit state") ${say(polkit)} ;; "pinentry state") ${say(pinentry)} ;; esac; exit 1`);
  put('qs', 'echo "Function not found" >&2; exit 1');
  put('niri', `echo '{"app_id":"org.gnome.TextEditor"}'`);
  for (const t of ['ydotool', 'wlrctl', 'dots-pointer', 'grim', 'curl']) put(t, `echo "${t} $*" >>'${log}'; exit ${inputExit}`);
  // Each wtype also notes when it began, in ms, for the spacing between keys.
  put('wtype', `echo $(( \${EPOCHREALTIME/./} / 1000 )) >>'${join(dir, 'wtype.ms')}'; echo "wtype $*" >>'${log}'; exit ${inputExit}`);
  // The journal and the desk state go to the scratch dir, never the live ~/.local/state or runtime dir.
  return { env: { ...process.env, PATH: `${dir}:${process.env.PATH}`, XDG_STATE_HOME: dir, XDG_RUNTIME_DIR: dir }, log, journal: join(dir, 'dots/agent-journal.ndjson'), wtypeMs: join(dir, 'wtype.ms') };
}

const locked = '{"locked":true,"secure":true}';
const unlocked = '{"locked":false,"secure":true,"heldBy":"claude","unlockedAt":1,"leaseUntil":2}';
const closed = '{"open":false,"loaded":false,"waiting":0}';
const open = '{"open":true,"settled":true,"field":0}';
const scripts = join(skill, 'scripts');
const inputs = [
  ['screen', 'type', 'hi'], ['screen', 'type', 'hi', '--any'], ['screen', 'key', 'Return'], ['screen', 'click', '1', '1'],
  ['screen', 'click', '1', '1', 'left', '1', '--any'], ['screen', 'drag', '1', '1', '2', '2'], ['screen', 'move', '1', '1'], ['screen', 'scroll', '1', '1', 'down'],
  ['mouse', 'click', '10', '10'], ['mouse', 'click', '10', '10', 'left', '1', '--any'], ['mouse', 'to', '10', '10'], ['mouse', 'drag', '1', '1', '2', '2'], ['mouse', 'scroll', '1', '1', 'down'],
  ['gui', 'click', 'files', 'Save'], ['gui', 'click', 'files', 'Save', '--any'], ['gui', 'type', 'files', 'Name', 'x'],
  ['screen', 'type', 'hi', '--then', 'shot'], ['screen', 'click', '1', '1', '--any', '--then', 'windows'], ['mouse', 'click', '10', '10', '--then', 'tree'],
  ['gui', 'click', 'files', 'Save', '--then', 'tree'], ['gui', 'type', 'files', 'Name', 'x', '--then', 'shot', '--any'],
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

// A key or a press at a password prompt lands in its field, so with the session unlocked an open polkit or pinentry prompt refuses every input path, --any too.
for (const prompt of ['polkit', 'pinentry']) {
  for (const [tool, ...args] of inputs) {
    test(`${tool} ${args.join(' ')} refuses while a ${prompt} prompt is open and sends no input`, () => {
      const { env, log } = stubs(unlocked, 1, { [prompt]: open });
      const r = spawnSync(join(scripts, tool), args, { env, encoding: 'utf8' });
      assert.equal(r.status, 3, r.stderr);
      assert.deepEqual(JSON.parse(r.stdout), { refused: 'auth prompt' });
      assert.doesNotMatch(readFileSync(log, 'utf8'), /^(wtype|ydotool|wlrctl|dots-pointer)/m);
    });
  }
}

// Anything but a literal "open": false counts as an open prompt.
for (const [why, prompts] of [['polkit state fails', { polkit: () => 'exit 1' }], ['pinentry state prints nothing', { pinentry: () => 'exit 0' }], ['polkit state says "false" as a string', { polkit: '{"open":"false"}' }]]) {
  for (const tool of [['mouse', 'click', '10', '10'], ['gui', 'click', 'files', 'Save'], ['screen', 'type', 'hi', '--any'], ['screen', 'key', 'Return', '--any']]) {
    test(`${tool.join(' ')} counts it as an open prompt when ${why}`, () => {
      const { env, log } = stubs(unlocked, 1, prompts);
      const r = spawnSync(join(scripts, tool[0]), tool.slice(1), { env, encoding: 'utf8' });
      assert.equal(r.status, 3, r.stderr);
      assert.deepEqual(JSON.parse(r.stdout), { refused: 'auth prompt' });
      assert.doesNotMatch(readFileSync(log, 'utf8'), /^(wtype|dots-pointer)/m);
    });
  }
}

// --any skips the agent-window check, which needs a niri; tests/dev/desk-keys.sh checks it.
test('screen type --any gets past the guard once lock state reads unlocked and both prompts closed', () => {
  const { env, log } = stubs(unlocked, 0);
  const r = spawnSync(screen, ['type', 'hi', '--any'], { env, encoding: 'utf8' });
  assert.equal(r.status, 0, r.stderr);
  const gate = 'dots-call lock state\ndots-call polkit state\ndots-call pinentry state\n';
  assert.equal(readFileSync(log, 'utf8'), `${gate}${gate}wtype -k Shift_L\n${gate}wtype -- h\n${gate}wtype -- i\n`);
});

const sent = (log, re) => readFileSync(log, 'utf8').split('\n').filter((l) => re.test(l));
// The shell answers lock state, or a prompt's state, with this once n keys have gone out.
const after = (n, then, before) => () => `if (( $(grep -c '^wtype -[-k] [^S]' "$(dirname "$0")/calls.log") >= ${n} )); then echo '${then}'; else echo '${before}'; fi; exit 0`;

// A lock or a password prompt can arrive between two keys of a burst, so every key re-reads both and the burst stops at the first that is not clear.
test('screen key Tab 50 with the session locking after key 10 sends at most 11 keys and exits 3', () => {
  const { env, log } = stubs(after(10, locked, unlocked), 0);
  const r = spawnSync(screen, ['key', 'Tab', '50', '--any'], { env, encoding: 'utf8' });
  assert.equal(r.status, 3, r.stderr);
  assert.deepEqual(JSON.parse(r.stdout), { refused: 'locked' });
  const keys = sent(log, /^wtype -k Tab$/).length;
  assert.ok(keys >= 10 && keys <= 11, `${keys} keys`);
});

test('a polkit prompt opening after key 5 of a 40-character screen type stops it within 6 keys', () => {
  const { env, log } = stubs(unlocked, 0, { polkit: after(5, open, closed) });
  const r = spawnSync(screen, ['type', 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMN', '--any'], { env, encoding: 'utf8' });
  assert.equal(r.status, 3, r.stderr);
  assert.deepEqual(JSON.parse(r.stdout), { refused: 'auth prompt' });
  const keys = sent(log, /^wtype -- /).map((l) => l.slice(9));
  assert.ok(keys.length >= 5 && keys.length <= 6, keys.join());
  assert.deepEqual(keys, [...'abcdef'].slice(0, keys.length));
});

test('screen type of 40 characters reads the lock and both prompts before each key', () => {
  const { env, log } = stubs(unlocked, 0);
  const text = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMN';
  assert.equal(spawnSync(screen, ['type', text, '--any'], { env, encoding: 'utf8' }).status, 0);
  const calls = readFileSync(log, 'utf8').trim().split('\n');
  const keys = calls.flatMap((l, i) => (l.startsWith('wtype -- ') ? [i] : []));
  assert.equal(keys.length, 40);
  for (const i of keys) assert.deepEqual(calls.slice(i - 3, i), ['dots-call lock state', 'dots-call polkit state', 'dots-call pinentry state']);
  assert.equal(keys.map((i) => calls[i].slice(9)).join(''), text);
});

test('keys go out at least 15 ms apart, for type and for a repeated key', () => {
  for (const args of [['type', 'abcdefghij', '--any'], ['key', 'ctrl+z', '10', '--any']]) {
    const { env, wtypeMs } = stubs(unlocked, 0);
    assert.equal(spawnSync(screen, args, { env, encoding: 'utf8' }).status, 0);
    const ms = readFileSync(wtypeMs, 'utf8').trim().split('\n').map(Number);
    assert.ok(ms.length >= 10, ms.join());
    const gaps = ms.slice(1).map((t, i) => t - ms[i]);
    assert.ok(Math.min(...gaps) >= 15, `${args[0]}: gaps ${gaps.join()}`);
  }
});

// A newline sent as Return would submit a form halfway, so type drops it, a CRLF's \r too; a character outside ASCII goes whole, even in the C locale.
test('screen type drops newlines and sends each character whole', () => {
  const { env, log } = stubs(unlocked, 0);
  assert.equal(spawnSync(screen, ['type', 'a\nb\r\né✓', '--any'], { env: { ...env, LC_ALL: 'C' }, encoding: 'utf8' }).status, 0);
  assert.deepEqual(sent(log, /^wtype -- /), ['wtype -- a', 'wtype -- b', 'wtype -- é', 'wtype -- ✓']);
  assert.doesNotMatch(readFileSync(log, 'utf8'), /Return/);
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

// A PATH holding only what doctor runs, so each tool is present only when the test puts it there.
function doctorEnv({ lock = unlocked, tools = ['grim', 'wtype', 'dots-pointer', 'ydotoold', 'tesseract'], a11y = true } = {}) {
  const dir = mkdtempSync(join(tmpdir(), 'desktop-doctor-'));
  const put = (name, body) => {
    writeFileSync(join(dir, name), `#!/bin/bash\n${body}\n`);
    chmodSync(join(dir, name), 0o755);
  };
  for (const t of ['bash', 'python3', 'dirname', 'readlink', 'date']) spawnSync('ln', ['-s', spawnSync('bash', ['-c', `command -v ${t}`], { encoding: 'utf8' }).stdout.trim(), join(dir, t)]);
  put('dots-call', `[[ "$*" == "lock state" ]] && echo '${lock}'`);
  put('niri', `case "$*" in
"msg -j outputs") echo '{"eDP-1":{"name":"eDP-1","logical":{"x":0,"y":0,"width":2048,"height":1280,"scale":1.25}}}' ;;
"msg -j focused-output") echo '{"name":"eDP-1","logical":{"x":0,"y":0,"width":2048,"height":1280,"scale":1.25}}' ;;
esac`);
  // The a11y bus's address, then the registry's root on it, as gui reaches them.
  put('dbus-send', a11y ? `[[ "$*" == *GetAddress* ]] && echo '   unix:path=/run/a11y'; [[ "$*" == *ChildCount* ]] && echo '   variant       int32 2'; exit 0` : 'exit 1');
  for (const t of tools) put(t, 'exit 0');
  return { ...process.env, PATH: dir, NIRI_SOCKET: join(dir, 'niri.sock'), XDG_RUNTIME_DIR: dir };
}
const doctor = (env) => {
  const r = spawnSync(screen, ['doctor'], { env, encoding: 'utf8' });
  return { status: r.status, out: r.stdout ? JSON.parse(r.stdout) : r.stderr };
};

test('screen doctor on a ready desktop has no blockers and exits 0', () => {
  const { status, out } = doctor(doctorEnv());
  assert.equal(status, 0, JSON.stringify(out));
  assert.deepEqual(out.blockers, []);
  assert.equal(out.next, null);
  assert.equal(out.locked, false);
  assert.deepEqual(out.lease, { by: 'claude', until: 2 });
  assert.equal(out.niri.ok, true);
  assert.match(out.niri.socket, /niri\.sock$/);
  assert.deepEqual(out.outputs, [{ name: 'eDP-1', focused: true, x: 0, y: 0, width: 2048, height: 1280, scale: 1.25 }]);
  assert.equal(out.at_spi, true);
  assert.deepEqual(out.tools, { grim: true, wtype: true, 'dots-pointer': true, ydotoold: true, tesseract: true });
});

test('screen doctor while locked names the lock and how to lift it', () => {
  const { status, out } = doctor(doctorEnv({ lock: locked }));
  assert.equal(status, 1);
  assert.deepEqual(out.blockers, ['locked']);
  assert.match(out.next, /dots-call lock unlock/);
});

test('screen doctor names a missing dots-pointer, and only a missing tool the skill needs blocks', () => {
  const { out } = doctor(doctorEnv({ tools: ['grim', 'wtype'] }));
  assert.deepEqual(out.blockers, ['dots-pointer']);
  assert.deepEqual(out.tools, { grim: true, wtype: true, 'dots-pointer': false, ydotoold: false, tesseract: false });
  assert.match(out.next, /chezmoi apply/);
});

test('screen doctor counts an a11y bus that does not answer as a blocker', () => {
  const { out } = doctor(doctorEnv({ a11y: false }));
  assert.equal(out.at_spi, false);
  assert.deepEqual(out.blockers, ['at-spi']);
  assert.match(out.next, /systemctl --user restart at-spi-dbus-bus\.service/);
});

test('screen doctor without a niri says so instead of dying', () => {
  const env = doctorEnv();
  delete env.NIRI_SOCKET;
  const { status, out } = doctor(env);
  assert.equal(status, 1);
  assert.deepEqual(out.niri, { socket: null, ok: false });
  assert.ok(out.blockers.includes('niri'), out.blockers);
});

test('screen doctor reaches the a11y bus AT_SPI_BUS_ADDRESS names, as libatspi does', () => {
  const env = doctorEnv({ a11y: false });
  writeFileSync(join(env.PATH, 'dbus-send'), `#!/bin/bash\n[[ "$*" == *--bus=unix:path=/run/nested-a11y* && "$*" == *ChildCount* ]] && echo '   variant       int32 1' && exit 0\nexit 1\n`);
  const { out } = doctor({ ...env, AT_SPI_BUS_ADDRESS: 'unix:path=/run/nested-a11y' });
  assert.equal(out.at_spi, true);
});

// A niri whose event stream replays a desktop with one foot window (id 1) on workspace 1, then sends `later`, a list of [seconds, event], and stays open.
function stream(later = [], { windows = [{ id: 1, app_id: 'foot', title: 'fish', is_focused: true, workspace_id: 1, pid: 10 }] } = {}) {
  const s = stubs(unlocked, 0);
  const dir = join(s.log, '..');
  const replay = [
    { WorkspacesChanged: { workspaces: [{ id: 1, idx: 1, name: null, output: 'eDP-1', is_active: true, is_focused: true }, { id: 2, idx: 2, name: 'web', output: 'eDP-1', is_active: false, is_focused: false }] } },
    { WindowsChanged: { windows } },
    { KeyboardLayoutsChanged: { keyboard_layouts: { names: ['us'], current_idx: 0 } } },
    { OverviewOpenedOrClosed: { is_open: false } },
  ];
  const lines = replay.map((e) => `echo '${JSON.stringify(e)}'`);
  for (const [t, e] of later) lines.push(`sleep ${t}`, `echo '${JSON.stringify(e)}'`);
  writeFileSync(join(dir, 'niri'), `#!/usr/bin/env bash\n[[ "$*" == "msg -j event-stream" ]] || exit 1\n${lines.join('\n')}\nexec sleep 100\n`);
  return { ...s, env: { ...s.env, NIRI_SOCKET: join(dir, 'niri.sock') } };
}
const wait = (env, ...args) => {
  const t0 = Date.now();
  const r = spawnSync(screen, ['wait', ...args], { env, encoding: 'utf8', timeout: 20000 });
  return { status: r.status, ms: Date.now() - t0, out: r.stdout ? JSON.parse(r.stdout) : r.stderr };
};
const opened = (id, app_id, title = app_id) => ({ WindowOpenedOrChanged: { window: { id, app_id, title, is_focused: false, workspace_id: 1, pid: 20 } } });

test('screen wait window-open returns at once with already when such a window is open', () => {
  const { status, out } = wait(stream().env, 'window-open', '--app', 'foot');
  assert.equal(status, 0, JSON.stringify(out));
  assert.equal(out.already, true);
  assert.equal(out.window.id, 1);
});

test('screen wait window-open returns the window that opens later', () => {
  const { status, out, ms } = wait(stream([[0.4, opened(7, 'org.gtk.WidgetFactory4')]]).env, 'window-open', '--app', 'org.gtk.WidgetFactory4');
  assert.equal(status, 0, JSON.stringify(out));
  assert.deepEqual([out.already, out.window.id, out.window.app_id], [false, 7, 'org.gtk.WidgetFactory4']);
  assert.ok(ms >= 400, `${ms} ms`);
});

test('screen wait title returns when the title comes to match', () => {
  const env = stream([[0.2, opened(1, 'foot', 'build')], [0.2, opened(1, 'foot', 'build done x')]]).env;
  const { status, out } = wait(env, 'title', '--id', '1', '--matches', 'x$');
  assert.equal(status, 0, JSON.stringify(out));
  assert.deepEqual([out.already, out.window.title], [false, 'build done x']);
});

test('screen wait focus, window-closed, workspace and overview follow their events', () => {
  const later = [[0.1, opened(5, 'kak')], [0.1, { WindowFocusChanged: { id: 5 } }], [0.1, { WorkspaceActivated: { id: 2, focused: true } }], [0.1, { OverviewOpenedOrClosed: { is_open: true } }], [0.1, { WindowClosed: { id: 1 } }]];
  assert.deepEqual(wait(stream(later).env, 'focus', '--id', '5').out.window.id, 5);
  assert.deepEqual(wait(stream(later).env, 'workspace', 'web').out.workspace.id, 2);
  assert.deepEqual(wait(stream(later).env, 'workspace', '2').out.workspace.name, 'web');
  assert.deepEqual(wait(stream(later).env, 'overview', 'open').out, { already: false, overview: 'open' });
  assert.deepEqual(wait(stream(later).env, 'window-closed', '--id', '1').out, { already: false, closed: 1 });
  assert.deepEqual(wait(stream().env, 'overview', 'closed').out, { already: true, overview: 'closed' });
});

test('screen wait gives up after its timeout with exit 1 and the last state seen', () => {
  const { status, out, ms } = wait(stream([[0.2, opened(3, 'kak', 'notes')]]).env, 'window-open', '--app', 'nothing', '--timeout', '1');
  assert.equal(status, 1);
  assert.ok(ms >= 1000 && ms < 1500, `${ms} ms`);
  assert.equal(out.timeout, 1);
  assert.deepEqual(out.last.windows.map((w) => [w.id, w.app_id, w.title]), [[1, 'foot', 'fish'], [3, 'kak', 'notes']]);
  assert.deepEqual([out.last.focused, out.last.workspace.id, out.last.overview], [1, 1, false]);
});

for (const bad of [['window-open', '--app', 'x', '--timeout', '61'], ['window-open', '--app', 'x', '--timeout', '0'], ['window-open'], ['title', '--id', '1'], ['focus', '--id', 'x'], ['overview', 'half'], ['nap']]) {
  test(`screen wait ${bad.join(' ')} is a usage error`, () => {
    assert.equal(wait(stream().env, ...bad).status, 2);
  });
}

for (const [tool, ...args] of [['screen', 'click', '1', '1', '--then', 'nope'], ['screen', 'type', 'hi', '--then'], ['mouse', 'click', '1', '1', '--then', 'pixels'], ['gui', 'click', 'files', 'Save', '--then', 'nope']]) {
  test(`${tool} ${args.join(' ')} is a usage error that sends nothing`, () => {
    const { env, log } = stubs(unlocked, 0);
    const r = spawnSync(join(scripts, tool), args, { env: { ...env, MOUSE_SCREEN: '100x100' }, encoding: 'utf8' });
    assert.equal(r.status, 2, r.stderr);
    assert.doesNotMatch(existsSync(log) ? readFileSync(log, 'utf8') : '', /wtype|dots-pointer/);
  });
}

// --then and its kind stay in the clear after the text, which is still kept as length and digest.
test('the journal keeps --then and its kind, and only the text goes', () => {
  const { env, journal } = stubs(locked, 1);
  spawnSync(screen, ['type', 'secret-value', '--then', 'shot'], { env, encoding: 'utf8' });
  spawnSync(join(scripts, 'gui'), ['type', 'files', 'Name', 'secret-value', '--any', '--then', 'tree'], { env, encoding: 'utf8' });
  const [scr, gui] = lines(journal);
  assert.equal(scr.args[1].len, 'secret-value'.length);
  assert.deepEqual(scr.args.slice(2), ['--then', 'shot']);
  assert.equal(gui.args[3].len, 'secret-value'.length);
  assert.deepEqual(gui.args.slice(4), ['--any', '--then', 'tree']);
  assert.doesNotMatch(readFileSync(journal, 'utf8'), /secret-value/);
});

// A shot of eDP-1, right of DP-1 at 1.25, maps its point onto eDP-1 and stays there, never pulled onto the focused DP-1.
test('a point in a shot of another output clicks that output at its own scale', () => {
  const { env, log } = twoOutputs();
  const state = join(env.XDG_RUNTIME_DIR, 'desk', 'niri.sock');
  mkdirSync(state, { recursive: true });
  writeFileSync(join(state, 'shot'), '1920 0 2048 1280 1280 800\n');
  spawnSync(screen, ['click', '640', '400', '--any'], { env, encoding: 'utf8' });
  assert.match(readFileSync(log, 'utf8'), /^dots-pointer 0,0,3968,1280 move 2944 640 click left$/m);
});

// wtype's keymap reaches a window only once a key has gone to it, so the first key into a window not typed into before is Shift_L, and only the first.
test('screen type and key prime a window not typed into before with Shift_L, once per window', () => {
  const { env, log } = stubs(unlocked, 0);
  const dir = join(log, '..');
  writeFileSync(join(dir, 'niri'), `#!/usr/bin/env bash\necho "{\\"id\\":$(cat '${dir}/focus'),\\"app_id\\":\\"x\\"}"\n`);
  const keys = () => sent(log, /^wtype /).map((l) => l.slice(6));
  const run = (id, ...args) => {
    writeFileSync(join(dir, 'focus'), `${id}`);
    writeFileSync(log, '');
    assert.equal(spawnSync(screen, [...args, '--any'], { env, encoding: 'utf8' }).status, 0);
    return keys();
  };
  assert.deepEqual(run(7, 'type', 'ab'), ['-k Shift_L', '-- a', '-- b']);
  assert.deepEqual(run(7, 'type', 'c'), ['-- c']);
  assert.deepEqual(run(7, 'key', 'Return'), ['-k Return']);
  assert.deepEqual(run(8, 'key', 'Return'), ['-k Shift_L', '-k Return']);
  assert.deepEqual(run(8, 'type', 'd'), ['-- d']);
});

// A click can wait up to 10 s behind another agent's gesture, and --any skips the hit-test's second read, so the prompts are read again once the gesture is this click's.
test('mouse click --any reads the prompts again once it holds the gesture lock', () => {
  const opensOnSecondRead = () => `if (( $(grep -c '^dots-call polkit state' "$(dirname "$0")/calls.log") >= 2 )); then echo '${open}'; else echo '${closed}'; fi; exit 0`;
  const { env, log } = stubs(unlocked, 0, { polkit: opensOnSecondRead });
  const r = spawnSync(join(scripts, 'mouse'), ['click', '10', '10', '--any'], { env: { ...env, MOUSE_SCREEN: '100x100' }, encoding: 'utf8' });
  assert.equal(r.status, 3, r.stderr);
  assert.deepEqual(JSON.parse(r.stdout), { refused: 'auth prompt' });
  assert.doesNotMatch(readFileSync(log, 'utf8'), /^dots-pointer/m);
});

// JEV sends a shot off the machine, so find and check do nothing without a brief's --jev: no guard read, no shot, no request, and a journal line with no send.
for (const args of [['find', 'the first text entry'], ['check', 'is anything open?'], ['find', 'the first text entry', '--any']]) {
  test(`screen ${args.join(' ')} without --jev refuses and sends nothing`, () => {
    const { env, log, journal } = stubs(unlocked, 0);
    const r = spawnSync(screen, args, { env, encoding: 'utf8' });
    assert.equal(r.status, 3, r.stderr);
    assert.deepEqual(JSON.parse(r.stdout), { refused: 'jev not granted' });
    assert.equal(existsSync(log) ? readFileSync(log, 'utf8') : '', '');
    const [line, ...more] = lines(journal);
    assert.deepEqual(more, []);
    assert.equal(line.outcome, 'refused');
    assert.deepEqual(line.args, args);
    assert.equal(line.jev, undefined);
  });
}

test('screen find and check need a description, and say how without a journal line', () => {
  const { env, journal } = stubs(unlocked, 0);
  for (const args of [['find'], ['check', '--jev'], ['find', '', '--jev'], ['check', 'a', 'b', '--jev']]) {
    const r = spawnSync(screen, args, { env, encoding: 'utf8' });
    assert.equal(r.status, 2, `${args}: ${r.stderr}`);
    assert.match(r.stderr + r.stdout, /screen find DESCRIPTION --jev/);
  }
  assert.ok(!existsSync(journal));
});

// A black RGB PNG of w x h.
function png(w, h) {
  const chunk = (type, data) => {
    const body = Buffer.concat([Buffer.from(type), data]);
    const len = Buffer.alloc(4);
    const crc = Buffer.alloc(4);
    len.writeUInt32BE(data.length);
    crc.writeUInt32BE(crc32(body));
    return Buffer.concat([len, body, crc]);
  };
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(w, 0);
  ihdr.writeUInt32BE(h, 4);
  ihdr[8] = 8;
  ihdr[9] = 2;
  return Buffer.concat([Buffer.from('89504e470d0a1a0a', 'hex'), chunk('IHDR', ihdr), chunk('IDAT', deflateSync(Buffer.alloc((w * 3 + 1) * h))), chunk('IEND', Buffer.alloc(0))]);
}
const pngSize = (b) => [b.readUInt32BE(16), b.readUInt32BE(20)];

const KEY = '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';
// The unlocked stubs, plus a grim that writes a w x h shot, a pass that holds KEY, and a curl that keeps its argv, its stdin and the body it was given, then answers `reply` with `status`.
function jevStubs({ w = 1280, h = 800, answers = {}, status = 200, reply } = {}) {
  const s = stubs(unlocked, 0);
  const dir = join(s.log, '..');
  const put = (name, body) => {
    writeFileSync(join(dir, name), `#!/usr/bin/env bash\n${body}\n`);
    chmodSync(join(dir, name), 0o755);
  };
  writeFileSync(join(dir, 'fixture.png'), png(w, h));
  put('grim', `echo "grim $*" >>'${s.log}'; cp '${join(dir, 'fixture.png')}' "\${@: -1}"`);
  put('pass', `echo "pass $* $PASSWORD_STORE_GPG_OPTS" >>'${s.log}'; [ "$*" = "show AI/openrouter/main" ] && printf '%s\\nurl: openrouter.ai\\n' '${KEY}'`);
  writeFileSync(join(dir, 'reply'), reply ?? JSON.stringify({ model: 'typesafe/jev-1.14', answers }));
  put('curl', [
    `echo "curl $*" >>'${s.log}'`,
    `printf '%s\\0' "$@" >'${join(dir, 'curl.argv')}'`,
    `cat >'${join(dir, 'curl.stdin')}'`,
    `prev=; for a in "$@"; do [ "$prev" = --data-binary ] && cp "\${a#@}" '${join(dir, 'curl.body')}'; prev=$a; done`,
    `cat '${join(dir, 'reply')}'; printf '\\n%s' '${status}'`,
  ].join('\n'));
  const env = { ...s.env, MOUSE_SCREEN: '2560x1600' };
  const argv = () => readFileSync(join(dir, 'curl.argv'), 'utf8').split('\0').slice(0, -1);
  const body = () => JSON.parse(readFileSync(join(dir, 'curl.body'), 'utf8'));
  const asset = () => Object.values(body().assets)[0];
  return { ...s, env, dir, argv, body, asset, stdin: () => readFileSync(join(dir, 'curl.stdin'), 'utf8') };
}
const box = (left, right, top, bottom, confidence = 0.9) => ({ type: 'box', box: { left, right, top, bottom }, confidence });
const noul = (p) => ({ type: 'noul', noul: p });
const run = (env, ...args) => spawnSync(screen, args, { env, encoding: 'utf8' });

test('screen find --jev sends one request with a Box and a Noul over a fresh shot, and prints the Box centre with both confidences', () => {
  const j = jevStubs({ answers: { target: box(0.25, 0.75, 0.5, 0.5, 0.92), on_screen: noul(0.97) } });
  const r = run(j.env, 'find', 'the first text entry', '--jev');
  assert.equal(r.status, 0, r.stderr);
  assert.deepEqual(JSON.parse(r.stdout), { x: 640, y: 400, confidence: 0.92, on_screen: 0.97 });
  assert.equal(sent(j.log, /^curl /).length, 1);
  const argv = j.argv();
  assert.equal(argv.at(-1), 'https://openrouter.ai/api/v1/systemone');
  assert.ok(argv.includes('TypeSafe-Danger-Zone-Images: true'), argv.join(' '));
  assert.equal(argv[argv.indexOf('--max-time') + 1], '10');
  assert.ok(!argv.some((a) => /retry/.test(a)), argv.join(' '));
  // The key reaches curl as a header on its stdin, never on its argv, where any process can read it.
  assert.equal(j.stdin(), `Authorization: Bearer ${KEY}\n`);
  assert.ok(!argv.some((a) => a.includes(KEY.slice(10, 18))));
  assert.match(readFileSync(j.log, 'utf8'), /^pass show AI\/openrouter\/main --pinentry-mode error$/m);
  const b = j.body();
  assert.equal(b.model, 'typesafe/jev-1.14');
  const [ref] = Object.keys(b.assets);
  assert.deepEqual(b.state, { shot: ref });
  assert.deepEqual(Object.keys(j.asset()).sort(), ['data_base64', 'format', 'type']);
  assert.equal(j.asset().type, 'image');
  assert.equal(j.asset().format, 'png');
  assert.deepEqual(Buffer.from(j.asset().data_base64, 'base64'), png(1280, 800));
  assert.equal(b.questions.target.type, 'box');
  assert.equal(b.questions.on_screen.type, 'noul');
  for (const q of Object.values(b.questions)) assert.ok(q.instructions.includes('the first text entry') && q.instructions.includes('`shot`'), q.instructions);
});

// The point is in the shot find took, which is the last shot, so screen click converts it through that shot's scale.
test('screen click takes the point find printed, through the shot find took', () => {
  const j = jevStubs({ answers: { target: box(0.25, 0.75, 0.5, 0.5), on_screen: noul(0.97) } });
  const { x, y } = JSON.parse(run(j.env, 'find', 'the first text entry', '--jev').stdout);
  assert.equal(run(j.env, 'click', `${x}`, `${y}`, '--any').status, 0);
  assert.match(readFileSync(j.log, 'utf8'), /^dots-pointer \S+ move 1280 800 click left$/m);
});

test('screen find exits 4 when the Noul says it is not on screen, and the journal says nothing was found', () => {
  const j = jevStubs({ answers: { target: box(0.1, 0.2, 0.1, 0.2), on_screen: noul(0.3) } });
  const r = run(j.env, 'find', 'a purple elephant', '--jev');
  assert.equal(r.status, 4, r.stderr);
  assert.deepEqual(JSON.parse(r.stdout), { found: false, on_screen: 0.3 });
  const [line] = lines(j.journal);
  assert.equal(line.outcome, 'nothing');
  assert.deepEqual(line.jev, { found: false, on_screen: 0.3 });
});

// A Box edge at 1.0 is the image's far edge, one past its last pixel, and screen click refuses a point there.
for (const [left, right, x] of [[0.98, 1.0, 1267], [1.0, 1.0, 1279], [0.0, 0.0, 0]]) {
  test(`a Box from ${left} to ${right} maps to x ${x}, inside the shot`, () => {
    const j = jevStubs({ answers: { target: box(left, right, 1.0, 1.0), on_screen: noul(0.9) } });
    const r = run(j.env, 'find', 'the close button', '--jev');
    assert.equal(r.status, 0, r.stderr);
    assert.deepEqual(JSON.parse(r.stdout), { x, y: 799, confidence: 0.9, on_screen: 0.9 });
  });
}

// JEV takes sides of at least 256 px; the padding goes right and below, so a point keeps its place in the shot.
test('a shot under 256 px a side goes padded to 256, and its point maps back into the unpadded shot', () => {
  const j = jevStubs({ w: 200, h: 100, answers: { target: box(0.2, 0.3, 0.1, 0.2), on_screen: noul(0.9) } });
  let r = run(j.env, 'find', 'the entry', '--jev');
  assert.equal(r.status, 0, r.stderr);
  assert.deepEqual(pngSize(Buffer.from(j.asset().data_base64, 'base64')), [256, 256]);
  assert.deepEqual(JSON.parse(r.stdout), { x: 64, y: 38, confidence: 0.9, on_screen: 0.9 });
  writeFileSync(join(j.dir, 'reply'), JSON.stringify({ answers: { target: box(0.98, 1.0, 0.98, 1.0), on_screen: noul(0.9) } }));
  r = run(j.env, 'find', 'the entry', '--jev');
  assert.deepEqual(JSON.parse(r.stdout), { x: 199, y: 99, confidence: 0.9, on_screen: 0.9 });
});

test('a shot of 256 px a side or more goes as it was taken', () => {
  const j = jevStubs({ w: 256, h: 300, answers: { target: box(0.5, 0.5, 0.5, 0.5), on_screen: noul(0.9) } });
  assert.equal(run(j.env, 'find', 'the entry', '--jev').status, 0);
  assert.deepEqual(Buffer.from(j.asset().data_base64, 'base64'), png(256, 300));
});

for (const [p, yes] of [[0.83, true], [0.5, true], [0.2, false]]) {
  test(`screen check --jev sends one Noul and says yes ${yes} at ${p}`, () => {
    const j = jevStubs({ answers: { answer: noul(p) } });
    const r = run(j.env, 'check', 'does a text entry read hi?', '--jev');
    assert.equal(r.status, 0, r.stderr);
    assert.deepEqual(JSON.parse(r.stdout), { yes, probability: p });
    const { questions } = j.body();
    assert.deepEqual(Object.values(questions).map((q) => q.type), ['noul']);
    assert.ok(questions.answer.instructions.includes('does a text entry read hi?') && questions.answer.instructions.includes('`shot`'));
  });
}

// Every send is a journal line with the question and the answer, never the image.
test('a send is a journal line with the question, the answer and its confidences, and no image data', () => {
  const j = jevStubs({ answers: { target: box(0.25, 0.75, 0.5, 0.5, 0.92), on_screen: noul(0.97) } });
  assert.equal(run(j.env, 'find', 'the first text entry', '--jev').status, 0);
  const [line, ...more] = lines(j.journal);
  assert.deepEqual(more, []);
  assert.equal(line.outcome, 'ok');
  assert.deepEqual(line.args, ['find', 'the first text entry', '--jev']);
  assert.deepEqual(line.jev, { x: 640, y: 400, confidence: 0.92, on_screen: 0.97 });
  const text = readFileSync(j.journal, 'utf8');
  assert.ok(text.length < 1000, `${text.length} bytes`);
  assert.ok(!text.includes(j.asset().data_base64.slice(0, 40)));
});

// OpenRouter could name the key it was sent in its error; no 8 characters of it reach the error message or the journal.
test('after a 401 from a wrong key, neither the error nor the journal holds any 8 characters of the key', () => {
  const j = jevStubs({ status: 401, reply: '{"error":{"message":"Invalid key: ' + KEY + '","code":401}}' });
  const r = run(j.env, 'find', 'the first text entry', '--jev');
  assert.equal(r.status, 1);
  assert.match(r.stderr, /401/);
  const said = r.stdout + r.stderr + readFileSync(j.journal, 'utf8');
  for (let i = 0; i + 8 <= KEY.length; i++) assert.ok(!said.includes(KEY.slice(i, i + 8)), `holds ${KEY.slice(i, i + 8)}: ${said}`);
  assert.equal(lines(j.journal)[0].outcome, 'error');
});

test('an answer without the questions it asked is a failure, exit 1', () => {
  const j = jevStubs({ answers: { on_screen: noul(0.9) } });
  const r = run(j.env, 'find', 'the first text entry', '--jev');
  assert.equal(r.status, 1, r.stdout);
  assert.match(r.stderr, /jev/);
});

// The real curl, through a proxy that takes the connection and never answers: --max-time bounds the whole call, and nothing tries again.
test('with OpenRouter unreachable, find exits 1 within 10.5 s, after one attempt', async () => {
  const j = jevStubs();
  unlinkSync(join(j.dir, 'curl'));
  let connections = 0;
  const held = [];
  const proxy = createServer((c) => {
    connections++;
    held.push(c);
  });
  await new Promise((ok) => proxy.listen(0, '127.0.0.1', ok));
  const url = `http://127.0.0.1:${proxy.address().port}`;
  const env = { ...j.env, https_proxy: url, HTTPS_PROXY: url, no_proxy: '', NO_PROXY: '' };
  const t0 = Date.now();
  const status = await new Promise((ok) => spawn(screen, ['find', 'the first text entry', '--jev'], { env, stdio: 'ignore' }).on('exit', ok));
  const took = Date.now() - t0;
  for (const c of held) c.destroy();
  proxy.close();
  assert.equal(status, 1);
  assert.ok(took <= 10500, `${took} ms`);
  assert.ok(took >= 9500, `${took} ms: it never waited for the timeout`);
  assert.equal(connections, 1);
});
