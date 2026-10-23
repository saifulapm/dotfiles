// The mobile toolchain script on a scratch home, against a scratch versions.toml whose downloads are local zips and whose sdkmanager and rustup log what they are asked.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { copyFileSync, existsSync, mkdirSync, mkdtempSync, readFileSync, readlinkSync, realpathSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const repo = new URL('../../', import.meta.url).pathname;
const SCRIPT = readFileSync(join(repo, 'home/.chezmoiscripts/run_onchange_after_47-mobile.sh.tmpl'), 'utf8');
const sha = (file) => createHash('sha256').update(readFileSync(file)).digest('hex');

// sdkmanager logs each call and makes the directory of each package it is asked for, the way the real one lays out the SDK.
const SDKMANAGER = `#!/bin/bash
echo "sdkmanager $*" >> "$HOME/calls.log"
case " $* " in *" --licenses "*) cat > /dev/null; exit 0 ;; esac
root=
for a in "$@"; do
  case $a in --sdk_root=*) root=\${a#--sdk_root=} ;; -*) ;; *) mkdir -p "$root/\${a//;//}" ;; esac
done
`;

// zip <dir> <name> <files>: a zip of the given {path: [body, mode]} files.
function zip(dir, name, files) {
  const work = mkdtempSync(join(dir, 'zip-'));
  for (const [path, [body, mode]] of Object.entries(files)) {
    mkdirSync(join(work, path, '..'), { recursive: true });
    writeFileSync(join(work, path), body, { mode });
  }
  const r = spawnSync('zip', ['-qr', join(dir, name), '.'], { cwd: work, encoding: 'utf8' });
  assert.equal(r.status, 0, r.stderr);
  return join(dir, name);
}

// A source dir with lib.sh and a versions.toml whose toolchain downloads are local zips, plus a home with a rustup that logs.
function world({ tools = '15859902', badSha = false } = {}) {
  const root = realpathSync(mkdtempSync(join(tmpdir(), 'dots-mobile-')));
  const [src, home, files] = ['src', 'home', 'files'].map((d) => join(root, d));
  mkdirSync(join(src, 'home/.chezmoitemplates'), { recursive: true });
  copyFileSync(join(repo, 'home/.chezmoitemplates/lib.sh'), join(src, 'home/.chezmoitemplates/lib.sh'));
  writeFileSync(join(src, '.chezmoiroot'), 'home\n');
  mkdirSync(join(home, '.cargo/bin'), { recursive: true });
  writeFileSync(join(home, '.cargo/bin/rustup'), '#!/bin/sh\necho "rustup $*" >> "$HOME/calls.log"\n', { mode: 0o755 });
  mkdirSync(files);
  const toolsZip = zip(files, `commandlinetools-linux-${tools}_latest.zip`, { 'cmdline-tools/bin/sdkmanager': [SDKMANAGER, 0o755], 'cmdline-tools/NOTICE.txt': [tools, 0o644] });
  const gradleZip = zip(files, 'gradle-9.7.1-bin.zip', { 'gradle-9.7.1/bin/gradle': ['#!/bin/sh\necho "Gradle 9.7.1"\n', 0o755] });
  writeFileSync(join(src, 'versions.toml'), `[[toolchain]]
name = "cmdline-tools"
version = "${tools}"
url = "file://${files}/commandlinetools-linux-{version}_latest.zip"
sha256 = "${badSha ? '0'.repeat(64) : sha(toolsZip)}"

[[toolchain]]
name = "platform"
version = "37.0"
package = "platforms;android-{version}"

[[toolchain]]
name = "build-tools"
version = "37.0.0"
package = "build-tools;{version}"

[[toolchain]]
name = "ndk"
version = "29.0.14206865"
package = "ndk;{version}"

[[toolchain]]
name = "gradle"
version = "9.7.1"
url = "file://${files}/gradle-{version}-bin.zip"
sha256 = "${sha(gradleZip)}"
`);
  return { root, src, home, files };
}

// run: renders the script for the given chezmoi arch and runs it on the world's home.
function run(w, arch = 'arm64') {
  const env = { PATH: process.env.PATH, HOME: w.home };
  const rendered = spawnSync('chezmoi', ['--config', join(w.root, 'none.toml'), '--source', w.src, '--override-data', JSON.stringify({ chezmoi: { arch } }), 'execute-template'], { input: SCRIPT, encoding: 'utf8', env });
  assert.equal(rendered.status, 0, rendered.stderr);
  return spawnSync('bash', ['-c', rendered.stdout], { encoding: 'utf8', env });
}

const calls = (w) => (existsSync(join(w.home, 'calls.log')) ? readFileSync(join(w.home, 'calls.log'), 'utf8').trim().split('\n') : []);

test('a fresh machine gets the command-line tools, the SDK packages, Gradle and rustup\'s Android targets', () => {
  const w = world();
  const r = run(w);
  assert.equal(r.status, 0, r.stderr);
  const sdk = join(w.home, 'Android/Sdk');
  assert.deepEqual(calls(w), [
    'rustup target add aarch64-linux-android x86_64-linux-android',
    `sdkmanager --sdk_root=${sdk} --licenses`,
    `sdkmanager --sdk_root=${sdk} platform-tools platforms;android-37.0 build-tools;37.0.0 ndk;29.0.14206865`,
  ]);
  assert.equal(readFileSync(join(sdk, 'cmdline-tools/latest/NOTICE.txt'), 'utf8'), '15859902');
  for (const dir of ['platform-tools', 'platforms/android-37.0', 'build-tools/37.0.0', 'ndk/29.0.14206865']) assert.ok(existsSync(join(sdk, dir)), dir);
  assert.equal(readlinkSync(join(w.home, '.local/bin/gradle')), join(w.home, '.local/opt/gradle-9.7.1/bin/gradle'));
  assert.equal(spawnSync(join(w.home, '.local/bin/gradle'), { encoding: 'utf8' }).stdout, 'Gradle 9.7.1\n');
});

// run_onchange reruns the script whenever any toolchain line changes, so what is in place must not be fetched or installed again.
test('a second run downloads nothing and asks sdkmanager for nothing', () => {
  const w = world();
  assert.equal(run(w).status, 0);
  rmSync(w.files, { recursive: true });
  rmSync(join(w.home, 'calls.log'));
  const r = run(w);
  assert.equal(r.status, 0, r.stderr);
  assert.deepEqual(calls(w), ['rustup target add aarch64-linux-android x86_64-linux-android']);
});

test('a newer command-line tools pin replaces the installed tools', () => {
  const w = world();
  assert.equal(run(w).status, 0);
  const moved = world({ tools: '16111833' });
  const r = run({ ...moved, home: w.home });
  assert.equal(r.status, 0, r.stderr);
  assert.equal(readFileSync(join(w.home, 'Android/Sdk/cmdline-tools/latest/NOTICE.txt'), 'utf8'), '16111833');
});

test('a command-line tools zip with the wrong sha256 stops the script and installs nothing', () => {
  const w = world({ badSha: true });
  const r = run(w);
  assert.notEqual(r.status, 0);
  assert.match(r.stderr, /dots: mobile: sha256 of .*commandlinetools-linux-15859902_latest\.zip is not 0{64}/);
  assert.equal(existsSync(join(w.home, 'Android/Sdk/cmdline-tools')), false);
});
