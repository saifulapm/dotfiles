// The pin.sh template against a scratch source whose one pin points at a local file, so no run reaches the network.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { copyFileSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, realpathSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const repo = new URL('../../', import.meta.url).pathname;
const sha = (s) => createHash('sha256').update(s).digest('hex');
const SCRIPT = `#!/bin/bash
{{ template "lib.sh" . }}
{{ template "pin.sh" (dict "chezmoi" .chezmoi "name" "hello") }}
file=$(pin_fetch)
cat "$file"
pin_done
`;

// A source dir holding the repo's lib.sh and pin.sh beside a versions.toml whose hello pin has the given sha256 on every arch.
function source(sum) {
  const root = realpathSync(mkdtempSync(join(tmpdir(), 'dots-pins-')));
  const templates = join(root, 'home/.chezmoitemplates');
  mkdirSync(templates, { recursive: true });
  for (const f of ['lib.sh', 'pin.sh']) copyFileSync(join(repo, 'home/.chezmoitemplates', f), join(templates, f));
  writeFileSync(join(root, '.chezmoiroot'), 'home\n');
  writeFileSync(join(root, 'hello-1.2.txt'), 'hello pin\n');
  const url = `file://${root}/hello-{version}.txt`;
  writeFileSync(
    join(root, 'versions.toml'),
    `[[pin]]\nname = "hello"\nversion = "1.2"\nrepo = "x/hello"\ncheck = "hello --version"\n` +
      `url.aarch64 = "${url}"\nurl.x86_64 = "${url}"\nsha256.aarch64 = "${sum}"\nsha256.x86_64 = "${sum}"\n`,
  );
  return root;
}

function renderOnly(root, script) {
  const rendered = spawnSync('chezmoi', ['--config', join(root, 'none.toml'), '--source', root, 'execute-template'], {
    input: script,
    encoding: 'utf8',
    env: { PATH: process.env.PATH, HOME: root },
  });
  assert.equal(rendered.status, 0, rendered.stderr);
  return rendered.stdout;
}

// path: stub dirs put before the real PATH.
function run(root, script = SCRIPT, path = '', env = {}) {
  return spawnSync('bash', ['-c', renderOnly(root, script)], { encoding: 'utf8', env: { PATH: path + process.env.PATH, HOME: root, ...env } });
}

test('a pin with the right sha256 is fetched and reported as changed', () => {
  const r = run(source(sha('hello pin\n')));
  assert.equal(r.status, 0, r.stderr);
  assert.equal(r.stdout, 'hello pin\ndots: pin hello 1.2\n');
});

// /tmp is a small tmpfs on the Macs, too small for a source build.
test('a pin is fetched and built under ~/.cache, not /tmp, and the dir is removed after', () => {
  const root = source(sha('hello pin\n'));
  const r = run(root, SCRIPT.replace('cat "$file"', 'echo "$file"'));
  assert.equal(r.status, 0, r.stderr);
  const file = r.stdout.split('\n')[0];
  assert.ok(file.startsWith(`${root}/.cache/`), file);
  assert.deepEqual(readdirSync(join(root, '.cache')), []);
});

test('a pin with a wrong sha256 stops the script, naming the pin', () => {
  const r = run(source('0'.repeat(64)));
  assert.notEqual(r.status, 0);
  assert.match(r.stderr, /pin hello: sha256/);
  assert.doesNotMatch(r.stdout, /dots: pin hello/);
});

// pin_cargo against a stub cargo that writes each binary it is asked for, or fails when $CARGO_FAIL is set.
const CARGO = `#!/bin/sh
[ -z "$CARGO_FAIL" ] || exit 101
while [ $# -gt 0 ]; do [ "$1" = --target-dir ] && t=$2; shift; done
mkdir -p "$t/release" && printf '#!/bin/sh\\necho built\\n' > "$t/release/hello" && chmod +x "$t/release/hello"
`;
function cargo(root, env = {}) {
  mkdirSync(join(root, 'stubs'));
  writeFileSync(join(root, 'stubs/cargo'), CARGO, { mode: 0o755 });
  const r = run(root, SCRIPT.replace('cat "$file"', 'mkdir -p "$pin_tmp/src"; pin_cargo "$pin_tmp/src" hello'), `${root}/stubs:`, env);
  return r;
}

test('pin_cargo installs each built binary into ~/.local/bin', () => {
  const root = source(sha('hello pin\n'));
  const r = cargo(root);
  assert.equal(r.status, 0, r.stderr);
  assert.equal(spawnSync(join(root, '.local/bin/hello'), { encoding: 'utf8' }).stdout, 'built\n');
  assert.match(r.stdout, /dots: pin hello 1\.2/);
});

// The apply has to say which tool did not build, not end on cargo's last line.
test('a failed cargo build stops the script, naming the pin', () => {
  const r = cargo(source(sha('hello pin\n')), { CARGO_FAIL: '1' });
  assert.notEqual(r.status, 0);
  assert.match(r.stderr, /dots: pin hello: cargo build failed/);
  assert.doesNotMatch(r.stdout, /dots: pin hello/);
});

// run_onchange keys a script on its rendered text, so a pin's change must show in its own script and no other.
test('changing one pin re-renders only that pin\'s script', () => {
  const dir = join(repo, 'home/.chezmoiscripts');
  const scripts = readdirSync(dir).filter((f) => /^run_onchange_after_2\d-pin-.+\.sh\.tmpl$/.test(f));
  const versions = readFileSync(join(repo, 'versions.toml'), 'utf8');
  const render = (toml) => {
    const root = source('0'.repeat(64));
    writeFileSync(join(root, 'versions.toml'), toml);
    return Object.fromEntries(scripts.map((f) => [f, renderOnly(root, readFileSync(join(dir, f), 'utf8'))]));
  };
  const base = render(versions);
  for (const name of ['amx']) {
    const moved = versions.replace(new RegExp(`(name = "${name}"\\nversion = ")[^"]+`), `$1${'f'.repeat(40)}`);
    assert.notEqual(moved, versions, `versions.toml has a ${name} pin`);
    const after = render(moved);
    assert.deepEqual(scripts.filter((f) => after[f] !== base[f]), scripts.filter((f) => f.endsWith(`-pin-${name}.sh.tmpl`)), name);
  }
});

test('every pin in versions.toml has its own script, and every pin script a pin', () => {
  const pins = [...readFileSync(join(repo, 'versions.toml'), 'utf8').matchAll(/^name = "([^"]+)"/gm)].map((m) => m[1]).sort();
  const scripts = readdirSync(join(repo, 'home/.chezmoiscripts'))
    .map((f) => f.match(/^run_onchange_after_2\d-pin-(.+)\.sh\.tmpl$/)?.[1])
    .filter(Boolean)
    .sort();
  assert.deepEqual(scripts, pins);
  for (const name of pins) {
    const [file] = readdirSync(join(repo, 'home/.chezmoiscripts')).filter((f) => f.endsWith(`-pin-${name}.sh.tmpl`));
    assert.match(readFileSync(join(repo, 'home/.chezmoiscripts', file), 'utf8'), new RegExp(`"name" "${name}"`), file);
  }
});
