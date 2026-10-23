// scrcpy is built from source on the Macs (arm64) and unpacked from the release on x86_64, against file:// fixtures so no run reaches the network.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { copyFileSync, lstatSync, mkdirSync, mkdtempSync, readFileSync, readlinkSync, realpathSync, statSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const repo = new URL('../../', import.meta.url).pathname;
const SCRCPY = 'home/.chezmoiscripts/run_onchange_after_29-pin-scrcpy.sh.tmpl';
const SERVER = 'home/.chezmoiscripts/run_onchange_after_29-pin-scrcpy-server.sh.tmpl';
const sha = (f) => createHash('sha256').update(readFileSync(f)).digest('hex');
const sh = (cmd, cwd) => {
  const r = spawnSync('bash', ['-c', cmd], { cwd, encoding: 'utf8' });
  assert.equal(r.status, 0, r.stderr);
};

// A source dir with the repo's scripts and templates and a versions.toml whose pins point at fixtures: a source tarball, a release tarball and a server file.
function source() {
  const root = realpathSync(mkdtempSync(join(tmpdir(), 'scrcpy-')));
  mkdirSync(join(root, 'home/.chezmoitemplates'), { recursive: true });
  mkdirSync(join(root, 'home/.chezmoiscripts'), { recursive: true });
  for (const f of ['lib.sh', 'pin.sh']) copyFileSync(join(repo, 'home/.chezmoitemplates', f), join(root, 'home/.chezmoitemplates', f));
  for (const f of [SCRCPY, SERVER]) copyFileSync(join(repo, f), join(root, f));
  writeFileSync(join(root, '.chezmoiroot'), 'home\n');
  const fx = join(root, 'fx');
  mkdirSync(join(fx, 'scrcpy-9.9.9/app'), { recursive: true });
  writeFileSync(join(fx, 'scrcpy-9.9.9/meson.build'), 'project()\n');
  mkdirSync(join(fx, 'scrcpy-linux-x86_64-v9.9.9'));
  writeFileSync(join(fx, 'scrcpy-linux-x86_64-v9.9.9/scrcpy'), '#!/bin/sh\necho scrcpy fixture\n', { mode: 0o755 });
  writeFileSync(join(fx, 'scrcpy-server-v9.9.9'), 'server bytes\n');
  sh('tar -czf src.tgz scrcpy-9.9.9 && tar -czf rel.tgz scrcpy-linux-x86_64-v9.9.9', fx);
  const toml = (name, body) => `[[pin]]\nname = "${name}"\nversion = "9.9.9"\nrepo = "x/scrcpy"\n${body}\n`;
  writeFileSync(
    join(root, 'versions.toml'),
    toml('scrcpy', `url.aarch64 = "file://${fx}/src.tgz"\nurl.x86_64 = "file://${fx}/rel.tgz"\nsha256.aarch64 = "${sha(join(fx, 'src.tgz'))}"\nsha256.x86_64 = "${sha(join(fx, 'rel.tgz'))}"`) +
      toml('scrcpy-server', `url = "file://${fx}/scrcpy-server-v9.9.9"\nsha256 = "${sha(join(fx, 'scrcpy-server-v9.9.9'))}"`),
  );
  return root;
}

function render(root, file, arch) {
  const r = spawnSync(
    'chezmoi',
    ['--config', join(root, 'none.toml'), '--source', root, 'execute-template', '--override-data', `{"chezmoi":{"arch":"${arch}"}}`],
    { input: readFileSync(join(root, file), 'utf8'), encoding: 'utf8', env: { PATH: process.env.PATH, HOME: root } },
  );
  assert.equal(r.status, 0, r.stderr);
  return r.stdout;
}

// Stub meson and ninja log their arguments, one per line, to $HOME/calls; meson fails when $MESON_FAIL is set.
function stubs(root) {
  const bin = join(root, 'stubs');
  mkdirSync(bin);
  writeFileSync(join(bin, 'meson'), '#!/bin/bash\n{ echo meson; printf "%s\\n" "$@"; } >>"$HOME/calls"\n[ -z "$MESON_FAIL" ]\n', { mode: 0o755 });
  writeFileSync(join(bin, 'ninja'), '#!/bin/bash\n{ echo ninja; printf "%s\\n" "$@"; } >>"$HOME/calls"\n', { mode: 0o755 });
  return `${bin}:`;
}

function run(root, file, arch, env = {}) {
  return spawnSync('bash', ['-c', render(root, file, arch)], { encoding: 'utf8', env: { PATH: stubs(root) + process.env.PATH, HOME: root, ...env } });
}

test('on arm64 scrcpy is configured for the prebuilt server and installed under ~/.local', () => {
  const root = source();
  const r = run(root, SCRCPY, 'arm64');
  assert.equal(r.status, 0, r.stderr);
  const calls = readFileSync(join(root, 'calls'), 'utf8').split('\n');
  const build = calls[2];
  assert.deepEqual(calls.slice(0, 2), ['meson', 'setup']);
  assert.ok(build.startsWith(`${root}/.cache/`), build);
  assert.match(calls[3], new RegExp(`^${root}/\\.cache/dots-pin-[^/]+/scrcpy-9\\.9\\.9$`));
  assert.deepEqual(calls.slice(4), [`--prefix=${root}/.local`, '--buildtype=release', '-Dcompile_server=false', 'ninja', '-C', build, 'install', '']);
  assert.match(r.stdout, /^dots: pin scrcpy 9\.9\.9$/m);
});

test('a failing meson stops the script, naming the pin', () => {
  const r = run(source(), SCRCPY, 'arm64', { MESON_FAIL: '1' });
  assert.notEqual(r.status, 0);
  assert.match(r.stderr, /scrcpy/);
  assert.doesNotMatch(r.stdout, /dots: pin scrcpy/);
});

test('on amd64 the release is unpacked under ~/.local/opt and linked into ~/.local/bin', () => {
  const root = source();
  const stale = join(root, '.local/opt/scrcpy-9.9.9');
  mkdirSync(stale, { recursive: true });
  writeFileSync(join(stale, 'old'), 'x');
  const r = run(root, SCRCPY, 'amd64');
  assert.equal(r.status, 0, r.stderr);
  const link = join(root, '.local/bin/scrcpy');
  assert.ok(lstatSync(link).isSymbolicLink());
  assert.equal(readlinkSync(link), join(root, '.local/opt/scrcpy-9.9.9/scrcpy'));
  assert.throws(() => statSync(join(stale, 'old')));
  const out = spawnSync(link, { encoding: 'utf8' });
  assert.equal(out.stdout, 'scrcpy fixture\n');
});

test('the server script renders empty on amd64 and installs the server mode 644 on arm64', () => {
  const root = source();
  assert.equal(render(root, SERVER, 'amd64').trim(), '');
  const r = run(root, SERVER, 'arm64');
  assert.equal(r.status, 0, r.stderr);
  const file = join(root, '.local/share/scrcpy/scrcpy-server');
  assert.equal(readFileSync(file, 'utf8'), 'server bytes\n');
  assert.equal(statSync(file).mode & 0o777, 0o644);
  assert.match(r.stdout, /^dots: pin scrcpy-server 9\.9\.9$/m);
});
