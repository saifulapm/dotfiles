// The pin.sh template against a scratch source whose one pin points at a local file, so no run reaches the network.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawn, spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { copyFileSync, existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, realpathSync, writeFileSync } from 'node:fs';
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
  for (const f of ['lib.sh', 'pin.sh', 'cargo.sh']) copyFileSync(join(repo, 'home/.chezmoitemplates', f), join(templates, f));
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
  const script = SCRIPT.replace('{{ template "pin.sh"', '{{ template "cargo.sh" . }}\n{{ template "pin.sh"').replace('cat "$file"', 'mkdir -p "$pin_tmp/src"; pin_cargo "$pin_tmp/src" hello');
  const r = run(root, script, `${root}/stubs:`, { DOTS_CARGO: `${root}/stubs/cargo`, ...env });
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
  assert.doesNotMatch(r.stdout, /^dots: pin hello [^:]*$/m);
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
  for (const name of ['amx', 'workflow', 'pxy']) {
    const moved = versions.replace(new RegExp(`(name = "${name}"\\nversion = ")[^"]+`), `$1${'f'.repeat(40)}`);
    assert.notEqual(moved, versions, `versions.toml has a ${name} pin`);
    const after = render(moved);
    assert.deepEqual(scripts.filter((f) => after[f] !== base[f]), scripts.filter((f) => f.endsWith(`-pin-${name}.sh.tmpl`)), name);
  }
});

test('every pin in versions.toml has its own script, and every pin script a pin', () => {
  // [[toolchain]] entries belong to the mobile script, so only [[pin]] blocks name a pin script.
  const blocks = readFileSync(join(repo, 'versions.toml'), 'utf8').split(/^(?=\[\[)/m).filter((b) => b.startsWith('[[pin]]'));
  const pins = blocks.map((b) => b.match(/^name = "([^"]+)"/m)[1]).sort();
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

// Every pin script renders pin.sh, so a helper only some pins use belongs in its own template, or editing it re-runs every pin.
test('every function pin.sh defines is called by every pin script', () => {
  const dir = join(repo, 'home/.chezmoiscripts');
  const fns = [...readFileSync(join(repo, 'home/.chezmoitemplates/pin.sh'), 'utf8').matchAll(/^(\w+)\(\) \{/gm)].map((m) => m[1]);
  assert.ok(fns.length >= 2, fns.join());
  for (const f of readdirSync(dir).filter((f) => /^run_onchange_after_2\d-pin-.+\.sh\.tmpl$/.test(f))) {
    const text = readFileSync(join(dir, f), 'utf8');
    assert.deepEqual(fns.filter((fn) => !new RegExp(`\\b${fn}\\b`).test(text)), [], f);
  }
});

// A private repo's pin: fetch = "gh" sends the download through gh api, and the sha256 check still stands.
function ghPin(sum) {
  const root = source(sum);
  const toml = readFileSync(join(root, 'versions.toml'), 'utf8').replace('repo = "x/hello"\n', 'repo = "x/hello"\nfetch = "gh"\n');
  writeFileSync(join(root, 'versions.toml'), toml);
  mkdirSync(join(root, 'stubs'));
  writeFileSync(join(root, 'stubs/gh'), '#!/bin/sh\n[ "$2" = repos/x/hello/tarball/1.2 ] && printf \'hello pin\\n\'\n', { mode: 0o755 });
  return root;
}

test('a fetch = "gh" pin downloads through gh api and prints the file', () => {
  const root = ghPin(sha('hello pin\n'));
  const r = run(root, SCRIPT, `${root}/stubs:`);
  assert.equal(r.status, 0, r.stderr);
  assert.equal(r.stdout, 'hello pin\ndots: pin hello 1.2\n');
});

test('a fetch = "gh" pin with a wrong sha256 stops the script', () => {
  const root = ghPin('0'.repeat(64));
  const r = run(root, SCRIPT, `${root}/stubs:`);
  assert.notEqual(r.status, 0);
  assert.match(r.stderr, /pin hello: sha256/);
});

// kakoune's Makefile installs with cp, which cannot write over a binary a running kak holds open (ETXTBSY), as on a machine with a kak session open.
test('the kakoune pin installs over a kak that is running', () => {
  const root = realpathSync(mkdtempSync(join(tmpdir(), 'dots-pin-kak-')));
  const home = join(root, 'home');
  const src = join(root, 'src');
  const stubs = join(root, 'stubs');
  for (const d of [join(home, '.local/bin'), join(src, 'src'), stubs]) mkdirSync(d, { recursive: true });
  copyFileSync('/usr/bin/sleep', join(home, '.local/bin/kak'));
  copyFileSync('/usr/bin/true', join(src, 'src/kak'));
  writeFileSync(join(stubs, 'make'), '#!/bin/sh\n[ "$3" = install ] || exit 0\ncp "$2/src/kak" "${4#PREFIX=}/bin/kak"\n', { mode: 0o755 });
  // The script's steps after the build, run with the build's own make replaced.
  const text = readFileSync(join(repo, 'home/.chezmoiscripts/run_onchange_after_21-pin-kakoune.sh.tmpl'), 'utf8');
  const steps = text.slice(text.indexOf('\n', text.indexOf('make -C "$src" -j')) + 1, text.indexOf('pin_done'));
  const running = spawn(join(home, '.local/bin/kak'), ['30']);
  try {
    const r = spawnSync('bash', ['-ec', steps], { encoding: 'utf8', env: { PATH: `${stubs}:${process.env.PATH}`, HOME: home, src } });
    assert.equal(r.status, 0, r.stderr);
    assert.deepEqual(readFileSync(join(home, '.local/bin/kak')), readFileSync('/usr/bin/true'));
  } finally {
    running.kill();
  }
});

// wlvncc's pin script against a scratch source whose wlvncc and aml pins point at local tarballs, with stub meson and ninja that log their argv and build a stand-in binary.
const WLVNCC = 'run_onchange_after_29-pin-wlvncc.sh.tmpl';
// As the real one does with --wrap-mode=nodownload, meson finds no aml unless it is unpacked in the source's subprojects/.
const MESON = `#!/bin/sh
echo "meson $*" >> "$HOME/calls"
[ -f "$3/subprojects/aml/meson.build" ] || { echo 'ERROR: Dependency "aml1" not found' >&2; exit 1; }
mkdir -p "$2"
`;
const NINJA = `#!/bin/sh
echo "ninja $*" >> "$HOME/calls"
printf '#!/bin/sh\\necho wlvncc\\n' > "$2/wlvncc" && chmod +x "$2/wlvncc"
`;
function wlvnccSource({ amlSum } = {}) {
  const root = source('0'.repeat(64));
  const tarball = (dir, file, body) => {
    mkdirSync(join(root, 'src', dir), { recursive: true });
    writeFileSync(join(root, 'src', dir, file), body);
    assert.equal(spawnSync('tar', ['-czf', join(root, `${dir}.tar.gz`), '-C', join(root, 'src'), dir]).status, 0);
    return sha(readFileSync(join(root, `${dir}.tar.gz`)));
  };
  const wlvncc = tarball(`wlvncc-${'c'.repeat(40)}`, 'meson.build', "project('wlvncc')\n");
  const aml = tarball('aml-1.0.0', 'meson.build', "project('aml')\n");
  writeFileSync(
    join(root, 'versions.toml'),
    `[[pin]]\nname = "wlvncc"\nversion = "${'c'.repeat(40)}"\nrepo = "any1/wlvncc"\ntrack = "commit"\nurl = "file://${root}/wlvncc-{version}.tar.gz"\nsha256 = "${wlvncc}"\n\n` +
      `[[pin]]\nname = "aml"\nversion = "1.0.0"\nrepo = "any1/aml"\nurl = "file://${root}/aml-{version}.tar.gz"\nsha256 = "${amlSum ?? aml}"\n`,
  );
  mkdirSync(join(root, 'stubs'));
  writeFileSync(join(root, 'stubs/meson'), MESON, { mode: 0o755 });
  writeFileSync(join(root, 'stubs/ninja'), NINJA, { mode: 0o755 });
  return root;
}
const wlvnccScript = () => readFileSync(join(repo, 'home/.chezmoiscripts', WLVNCC), 'utf8');

test('wlvncc builds with aml unpacked as its subproject, never downloading, and installs into ~/.local/bin', () => {
  const root = wlvnccSource();
  const r = run(root, wlvnccScript(), `${root}/stubs:`);
  assert.equal(r.status, 0, r.stderr);
  const calls = readFileSync(join(root, 'calls'), 'utf8').trim().split('\n');
  assert.equal(calls.length, 2, calls.join('\n'));
  assert.match(calls[0], /^meson setup \S+ \S+ /);
  assert.match(calls[0], / --wrap-mode=nodownload( |$)/);
  // Installed shared, libaml.so would sit in ~/.local/lib64, where the loader never looks.
  assert.match(calls[0], / -Daml:default_library=static( |$)/);
  assert.match(calls[1], /^ninja -C \S+$/);
  assert.equal(spawnSync(join(root, '.local/bin/wlvncc'), { encoding: 'utf8' }).stdout, 'wlvncc\n');
  assert.match(r.stdout, new RegExp(`dots: pin wlvncc ${'c'.repeat(40)}`));
  assert.deepEqual(readdirSync(join(root, '.cache')), []);
});

test("a wrong aml sha256 stops wlvncc's build before meson, naming aml", () => {
  const root = wlvnccSource({ amlSum: '0'.repeat(64) });
  const r = run(root, wlvnccScript(), `${root}/stubs:`);
  assert.notEqual(r.status, 0);
  assert.match(r.stderr, /pin aml: sha256/);
  assert.equal(existsSync(join(root, 'calls')), false);
  assert.equal(existsSync(join(root, '.local/bin/wlvncc')), false);
});

// aml is built into wlvncc, so a change to aml's pin alone must re-render, and so rerun, wlvncc's script.
test("changing only aml's sha256 re-renders aml's and wlvncc's scripts and no other", () => {
  const dir = join(repo, 'home/.chezmoiscripts');
  const scripts = readdirSync(dir).filter((f) => /^run_onchange_after_2\d-pin-.+\.sh\.tmpl$/.test(f));
  const versions = readFileSync(join(repo, 'versions.toml'), 'utf8');
  const render = (toml) => {
    const root = source('0'.repeat(64));
    writeFileSync(join(root, 'versions.toml'), toml);
    return Object.fromEntries(scripts.map((f) => [f, renderOnly(root, readFileSync(join(dir, f), 'utf8'))]));
  };
  const moved = versions.replace(/(name = "aml"\n(?:[^[\n][^\n]*\n)*?sha256 = ")[0-9a-f]+/, `$1${'e'.repeat(64)}`);
  assert.notEqual(moved, versions, 'versions.toml has an aml pin with a sha256');
  const base = render(versions);
  const after = render(moved);
  assert.deepEqual(scripts.filter((f) => after[f] !== base[f]).sort(), ['run_onchange_after_29-pin-aml.sh.tmpl', WLVNCC]);
});
