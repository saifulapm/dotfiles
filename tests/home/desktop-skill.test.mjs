// The desktop skill and its two operators name only v2's commands and the shell's real IPC targets, and scripts/screen types nothing while the session is locked.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { chmodSync, existsSync, mkdtempSync, readdirSync, readFileSync, writeFileSync } from 'node:fs';
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

// A PATH whose dots-call answers lock state with the given JSON, whose dots-call and input tools log their argv to one file, in call order, and whose niri says a plain app has focus.
function stubs(lockState, inputExit) {
  const dir = mkdtempSync(join(tmpdir(), 'desktop-skill-'));
  const log = join(dir, 'calls.log');
  const put = (name, body) => {
    writeFileSync(join(dir, name), `#!/usr/bin/env bash\n${body}\n`);
    chmodSync(join(dir, name), 0o755);
  };
  put('dots-call', `echo "dots-call $*" >>'${log}'; [[ "$*" == "lock state" ]] && { echo '${lockState}'; exit 0; }; exit 1`);
  put('qs', 'echo "Function not found" >&2; exit 1');
  put('niri', `echo '{"app_id":"org.gnome.TextEditor"}'`);
  for (const t of ['wtype', 'ydotool', 'wlrctl']) put(t, `echo "${t} $*" >>'${log}'; exit ${inputExit}`);
  return { env: { ...process.env, PATH: `${dir}:${process.env.PATH}` }, log };
}

const locked = '{"locked":true,"secure":true}';

for (const args of [['type', 'hi'], ['key', 'Return'], ['click', '1', '1']]) {
  test(`screen ${args[0]} refuses while the session is locked and sends no input`, () => {
    const { env, log } = stubs(locked, 1);
    const r = spawnSync(screen, args, { env, encoding: 'utf8' });
    assert.equal(r.status, 1, r.stderr);
    assert.match(r.stderr, /locked/);
    assert.equal(existsSync(log) ? readFileSync(log, 'utf8') : '', 'dots-call lock state\n');
  });
}

test('screen type gets past the guard once lock state reads unlocked', () => {
  const { env, log } = stubs('{"locked":false,"secure":true,"heldBy":"claude","unlockedAt":1,"leaseUntil":2}', 0);
  const r = spawnSync(screen, ['type', 'hi'], { env, encoding: 'utf8' });
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
