// The mobile toolchain script on a scratch home, against a scratch versions.toml whose downloads are local zips and whose sdkmanager and rustup log what they are asked.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { copyFileSync, existsSync, mkdirSync, mkdtempSync, readFileSync, readlinkSync, realpathSync, rmSync, statSync, writeFileSync } from 'node:fs';
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

// swiftly logs each call: init moves it into SWIFTLY_BIN_DIR, install makes the toolchain and its proxies, and SWIFT_DEPS stands for the packages a toolchain wants.
const SWIFTLY = `#!/bin/bash
[ "$1" = --version ] && { echo 1.1.3; exit 0; }
echo "swiftly $*" | sed "s|$HOME/.cache/[^ ]*|<tmp>|g" >> "$HOME/calls.log"
case $1 in
  init) mkdir -p "$SWIFTLY_BIN_DIR"; cp "$0" "$SWIFTLY_BIN_DIR/swiftly" ;;
  install)
    mkdir -p "$SWIFTLY_HOME_DIR/toolchains/$2"
    for b in swift swiftc clang; do printf '#!/bin/sh\\necho "%s"\\n' "$b $2" > "$SWIFTLY_BIN_DIR/$b"; chmod +x "$SWIFTLY_BIN_DIR/$b"; done
    while [ $# -gt 0 ]; do [ "$1" = --post-install-file ] && printf '%s' "$SWIFT_DEPS" > "$2"; shift; done
    ;;
esac
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
  const swiftlyDir = mkdtempSync(join(files, 'swiftly-'));
  writeFileSync(join(swiftlyDir, 'swiftly'), SWIFTLY, { mode: 0o755 });
  const swiftlyTar = join(files, 'swiftly-1.1.3.tar.gz');
  const tar = spawnSync('tar', ['-czf', swiftlyTar, '-C', swiftlyDir, 'swiftly'], { encoding: 'utf8' });
  assert.equal(tar.status, 0, tar.stderr);
  mkdirSync(join(files, 'arm'));
  for (const f of ['aapt2', 'zipalign']) writeFileSync(join(files, 'arm', f), `arm64 ${f}\n`);
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
name = "arm-build-tools"
version = "37.0.0"
url = "file://${files}/arm"
sha256.aapt2 = "${sha(join(files, 'arm/aapt2'))}"
sha256.zipalign = "${sha(join(files, 'arm/zipalign'))}"

[[toolchain]]
name = "gradle"
version = "9.7.1"
url = "file://${files}/gradle-{version}-bin.zip"
sha256 = "${sha(gradleZip)}"

[[toolchain]]
name = "swiftly"
version = "1.1.3"
url.aarch64 = "file://${swiftlyTar}"
url.x86_64 = "file://${swiftlyTar}"
sha256.aarch64 = "${sha(swiftlyTar)}"
sha256.x86_64 = "${sha(swiftlyTar)}"

[[toolchain]]
name = "swift"
version = "6.3.3"
platform = "fedora39"
`);
  return { root, src, home, files };
}

// run: renders the script for the given chezmoi arch and runs it on the world's home.
function run(w, arch = 'arm64', extra = {}) {
  const env = { PATH: process.env.PATH, HOME: w.home, ...extra };
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
    'swiftly init --platform fedora39 --skip-install --no-modify-profile --quiet-shell-followup --assume-yes',
    'swiftly install 6.3.3 --use --assume-yes --post-install-file <tmp>',
  ]);
  assert.equal(readFileSync(join(sdk, 'cmdline-tools/latest/NOTICE.txt'), 'utf8'), '15859902');
  for (const dir of ['platform-tools', 'platforms/android-37.0', 'build-tools/37.0.0', 'ndk/29.0.14206865']) assert.ok(existsSync(join(sdk, dir)), dir);
  assert.equal(readlinkSync(join(w.home, '.local/bin/gradle')), join(w.home, '.local/opt/gradle-9.7.1/bin/gradle'));
  assert.equal(spawnSync(join(w.home, '.local/bin/gradle'), { encoding: 'utf8' }).stdout, 'Gradle 9.7.1\n');
});

// run_onchange reruns the script whenever any toolchain line changes, so what is in place must not be fetched or installed again.
test('a second run downloads nothing and asks sdkmanager and swiftly for nothing', () => {
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

// Google builds aapt2, zipalign and adb for x86_64 only, and AGP runs the aapt2 it fetches from Maven unless gradle.properties names another.
test('on the Macs the arm64 aapt2 and zipalign replace Google\'s, Gradle is pointed at that aapt2, and adb is Fedora\'s', () => {
  const w = world();
  mkdirSync(join(w.home, '.gradle'));
  writeFileSync(join(w.home, '.gradle/gradle.properties'), 'org.gradle.daemon=false\nandroid.aapt2FromMavenOverride=/old/build-tools/36.0.0/aapt2\n');
  const r = run(w, 'arm64');
  assert.equal(r.status, 0, r.stderr);
  const bt = join(w.home, 'Android/Sdk/build-tools/37.0.0');
  for (const f of ['aapt2', 'zipalign']) {
    assert.equal(readFileSync(join(bt, f), 'utf8'), `arm64 ${f}\n`);
    assert.equal(statSync(join(bt, f)).mode & 0o777, 0o755, f);
  }
  assert.equal(readFileSync(join(w.home, '.gradle/gradle.properties'), 'utf8'), `org.gradle.daemon=false\nandroid.aapt2FromMavenOverride=${bt}/aapt2\n`);
  for (const f of ['adb', 'fastboot']) assert.equal(readlinkSync(join(w.home, 'Android/Sdk/platform-tools', f)), `/usr/bin/${f}`);
});

test('x86_64 keeps Google\'s build tools and adb and leaves gradle.properties alone', () => {
  const w = world();
  const r = run(w, 'amd64');
  assert.equal(r.status, 0, r.stderr);
  assert.equal(existsSync(join(w.home, 'Android/Sdk/build-tools/37.0.0/aapt2')), false);
  assert.equal(existsSync(join(w.home, '.gradle/gradle.properties')), false);
  assert.equal(existsSync(join(w.home, 'Android/Sdk/platform-tools/adb')), false);
});

// swiftly's bin dir also proxies clang and lld, which would shadow the distribution clang the engine's Android linker runs on the Macs.
test('Swift comes through swiftly, and only swift and swiftc are linked into ~/.local/bin', () => {
  const w = world();
  const r = run(w);
  assert.equal(r.status, 0, r.stderr);
  const bin = join(w.home, '.local/share/swiftly/bin');
  for (const b of ['swift', 'swiftc']) assert.equal(readlinkSync(join(w.home, '.local/bin', b)), join(bin, b));
  assert.equal(spawnSync(join(w.home, '.local/bin/swift'), { encoding: 'utf8' }).stdout, 'swift 6.3.3\n');
  assert.equal(existsSync(join(w.home, '.local/bin/clang')), false);
});

// The system packages a toolchain needs come from packages.toml, so an apply that lacks one says which.
test('a Swift that wants system packages stops the script and names them', () => {
  const w = world();
  const r = run(w, 'arm64', { SWIFT_DEPS: 'dnf -y install libstdc++-static\n' });
  assert.notEqual(r.status, 0);
  assert.match(r.stderr, /dots: mobile: Swift 6\.3\.3 wants system packages packages\.toml lacks: dnf -y install libstdc\+\+-static/);
});
