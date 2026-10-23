// dots bump against a scratch repo copy, with a stub gh and curl first on PATH so nothing reaches GitHub.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { chmodSync, copyFileSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { delimiter, join } from 'node:path';

const bin = new URL('../../bin/', import.meta.url).pathname;
const sha = (s) => createHash('sha256').update(s).digest('hex');
const OLD = '0'.repeat(64);
const YAZI = 'https://github.com/sxyazi/yazi/releases/download/v{version}/yazi-';
const KAK_OLD = 'be31e203e2948031bdde6cb573cfafa75158e228';
const KAK_NEW = '1234567890abcdef1234567890abcdef12345678';

const FILE = `# pins, bumped by dots bump
[[pin]]
name = "yazi"
version = "26.9.1"
repo = "sxyazi/yazi"
install = "~/.local/bin/yazi and ~/.local/bin/ya"
check = "yazi --version"
url.aarch64 = "${YAZI}aarch64-unknown-linux-gnu.zip"
url.x86_64 = "${YAZI}x86_64-unknown-linux-gnu.zip"
sha256.aarch64 = "${OLD}"
sha256.x86_64 = "${OLD}" # keep this comment

[[pin]]
name = "kakoune"
version = "${KAK_OLD}"
repo = "saifulapm/kakoune"
track = "commit"
install = "~/.local/bin/kak, built from source"
check = "kak -version"
url = "https://github.com/saifulapm/kakoune/archive/{version}.tar.gz"
sha256 = "${OLD}"
`;

// gh api repos/<owner>/<name>/<what> --jq <expr>: prints $FIX/gh/<owner>_<name>, or an error body on stdout and exit 1 when <owner>_<name>.fail exists; a tarball/<sha> path prints $FIX/gh/tarball_<sha>.
const STUB_GH = `#!/bin/sh
case $2 in */tarball/*) cat "$FIX/gh/tarball_\${2##*/}"; exit ;; esac
key=$(echo "$2" | cut -d/ -f2,3 | tr / _)
if [ -e "$FIX/gh/$key.fail" ]; then echo '{"message":"Not Found","status":"404"}'; exit 1; fi
cat "$FIX/gh/$key"
`;

// curl -fsSL <url> [-o file]: serves $FIX/curl/<url with non-alphanumerics as _>, and fails when there is none.
const STUB_CURL = `#!/bin/sh
out=
url=
while [ $# -gt 0 ]; do
  case $1 in -o) out=$2; shift ;; -*) ;; *) url=$1 ;; esac
  shift
done
f="$FIX/curl/$(printf %s "$url" | tr -c 'A-Za-z0-9' _)"
[ -f "$f" ] || { echo "curl: no fixture for $url" >&2; exit 22; }
if [ -n "$out" ]; then cp "$f" "$out"; else cat "$f"; fi
`;

// A scratch repo with bin/dots and bin/dots-bump copied in, plus the stubs and fixtures.
function world({ yaziTag, kakSha, yaziFails = false, file = FILE }) {
  const root = realpathSync(mkdtempSync(join(tmpdir(), 'dots-bump-')));
  const [repo, stubs, fix] = ['repo', 'stubs', 'fix'].map((d) => join(root, d));
  for (const d of [join(repo, 'bin'), stubs, join(fix, 'gh'), join(fix, 'curl'), join(root, 'home')]) mkdirSync(d, { recursive: true });
  for (const f of ['dots', 'dots-bump']) copyFileSync(bin + f, join(repo, 'bin', f));
  for (const f of ['dots', 'dots-bump']) chmodSync(join(repo, 'bin', f), 0o755);
  writeFileSync(join(stubs, 'gh'), STUB_GH, { mode: 0o755 });
  writeFileSync(join(stubs, 'curl'), STUB_CURL, { mode: 0o755 });
  writeFileSync(join(fix, 'gh/sxyazi_yazi'), yaziTag + '\n');
  writeFileSync(join(fix, 'gh/saifulapm_kakoune'), kakSha + '\n');
  if (yaziFails) writeFileSync(join(fix, 'gh/sxyazi_yazi.fail'), '');
  const serve = (url, body) => writeFileSync(join(fix, 'curl', url.replace(/[^A-Za-z0-9]/g, '_')), body);
  const yazi = YAZI.replace('{version}', '26.10.0');
  serve(`${yazi}aarch64-unknown-linux-gnu.zip`, 'yazi arm 26.10.0');
  serve(`${yazi}x86_64-unknown-linux-gnu.zip`, 'yazi x86 26.10.0');
  serve(`https://github.com/saifulapm/kakoune/archive/${KAK_NEW}.tar.gz`, 'kakoune new');
  writeFileSync(join(repo, 'versions.toml'), file);
  const env = { PATH: stubs + delimiter + process.env.PATH, HOME: join(root, 'home'), FIX: fix };
  return {
    fix,
    serve,
    bump: () => spawnSync(join(repo, 'bin/dots'), ['bump'], { env, encoding: 'utf8' }),
    read: () => readFileSync(join(repo, 'versions.toml'), 'utf8'),
  };
}

// The lines of b that differ from the same line of a; bump never adds or removes a line.
const changed = (a, b) => {
  const [x, y] = [a.split('\n'), b.split('\n')];
  assert.equal(x.length, y.length);
  return y.filter((l, i) => l !== x[i]);
};

test('one pin with a newer release is rewritten and named on one line', () => {
  const w = world({ yaziTag: 'v26.10.0', kakSha: KAK_OLD });
  const before = w.read();
  const r = w.bump();
  assert.equal(r.status, 0, r.stderr);
  assert.equal(r.stdout, 'yazi 26.9.1 → 26.10.0\n');
  assert.deepEqual(changed(before, w.read()), [
    'version = "26.10.0"',
    `sha256.aarch64 = "${sha('yazi arm 26.10.0')}"`,
    `sha256.x86_64 = "${sha('yazi x86 26.10.0')}" # keep this comment`,
  ]);
});

test('no newer release prints all pins current and leaves the file alone', () => {
  const w = world({ yaziTag: 'v26.9.1', kakSha: KAK_OLD });
  const before = w.read();
  const r = w.bump();
  assert.equal(r.status, 0, r.stderr);
  assert.equal(r.stdout, 'all pins current\n');
  assert.equal(w.read(), before);
});

test('a track=commit pin moves to the new head sha and its one sha256 is rewritten', () => {
  const w = world({ yaziTag: 'v26.9.1', kakSha: KAK_NEW });
  const before = w.read();
  const r = w.bump();
  assert.equal(r.status, 0, r.stderr);
  assert.equal(r.stdout, `kakoune ${KAK_OLD} → ${KAK_NEW}\n`);
  assert.deepEqual(changed(before, w.read()), [`version = "${KAK_NEW}"`, `sha256 = "${sha('kakoune new')}"`]);
});

test('a gh failure leaves that pin untouched, bumps the other and exits 1', () => {
  const w = world({ yaziTag: 'v26.10.0', kakSha: KAK_NEW, yaziFails: true });
  const before = w.read();
  const r = w.bump();
  assert.equal(r.status, 1);
  assert.equal(r.stdout, `kakoune ${KAK_OLD} → ${KAK_NEW}\n`);
  assert.match(r.stderr, /yazi/);
  assert.deepEqual(changed(before, w.read()), [`version = "${KAK_NEW}"`, `sha256 = "${sha('kakoune new')}"`]);
});

// amx, workflow and pxy follow main's head; with every other pin current, a bump names those three, one line each.
test('the agent tools move to their repos\' head commits, one line each', () => {
  const file = readFileSync(new URL('../../versions.toml', import.meta.url), 'utf8');
  const entries = (table) => file.split(/^(?=\[\[)/m).filter((b) => b.startsWith(`[[${table}]]`))
    .map((p) => Object.fromEntries([...p.matchAll(/^(name|version|repo|track|url|latest|package) = "([^"]*)"/gm)].map((m) => [m[1], m[2]])));
  const pins = entries('pin');
  const toolchain = entries('toolchain');
  const w = world({ yaziTag: 'v26.9.1', kakSha: KAK_OLD, file });
  // Every toolchain entry's upstream answers with the version it already has.
  const v = (name) => toolchain.find((t) => t.name === name).version;
  w.serve(SDK, sdkXml({ ndk: v('ndk'), tools: v('cmdline-tools'), platform: v('platform'), buildTools: v('build-tools') }));
  w.serve(SWIFT, swiftJson([v('swift')]));
  for (const t of toolchain.filter((t) => t.latest === 'github')) writeFileSync(join(w.fix, 'gh', t.repo.replace('/', '_')), `v${t.version}\n`);
  const head = { amx: 'a'.repeat(40), workflow: 'b'.repeat(40), pxy: 'c'.repeat(40) };
  for (const p of pins) {
    const latest = head[p.name] ?? (p.track === 'commit' ? p.version : `v${p.version}`);
    writeFileSync(join(w.fix, 'gh', p.repo.replace('/', '_')), latest + '\n');
    if (head[p.name]) w.serve(p.url.replace('{version}', latest), `${p.name} head`);
  }
  const r = w.bump();
  assert.equal(r.status, 0, r.stderr);
  const old = Object.fromEntries(pins.map((p) => [p.name, p.version]));
  assert.equal(r.stdout, ['amx', 'workflow', 'pxy'].map((n) => `${n} ${old[n]} → ${head[n]}\n`).join('') + toolchain.map((t) => `toolchain ${t.name} ${t.version} is current\n`).join(''));
  for (const n of ['amx', 'workflow', 'pxy']) assert.match(w.read(), new RegExp(`name = "${n}"\nversion = "${head[n]}"`));
});

// kakfeed is private: its pin says fetch = "gh", so the new tarball comes from gh api, never curl (the stub curl has no fixture for it).
test('a fetch = "gh" pin is hashed from the tarball gh api downloads', () => {
  const file = FILE + `
[[pin]]
name = "kakfeed"
version = "${KAK_OLD}"
repo = "saifulapm/kakfeed"
track = "commit"
fetch = "gh"
url = "https://github.com/saifulapm/kakfeed/archive/{version}.tar.gz"
sha256 = "${OLD}"
`;
  const w = world({ yaziTag: 'v26.9.1', kakSha: KAK_OLD, file });
  writeFileSync(join(w.fix, 'gh/saifulapm_kakfeed'), KAK_NEW + '\n');
  writeFileSync(join(w.fix, `gh/tarball_${KAK_NEW}`), 'kakfeed private tarball');
  const before = w.read();
  const r = w.bump();
  assert.equal(r.status, 0, r.stderr);
  assert.equal(r.stdout, `kakfeed ${KAK_OLD} → ${KAK_NEW}\n`);
  assert.deepEqual(changed(before, w.read()), [`version = "${KAK_NEW}"`, `sha256 = "${sha('kakfeed private tarball')}"`]);
});

const SDK = 'https://dl.google.com/android/repository/repository2-3.xml';
const SWIFT = 'https://www.swift.org/api/v1/install/releases.json';
const TOOLCHAIN = `
[[toolchain]]
name = "cmdline-tools"
version = "15859902"
latest = "sdk"
package = "cmdline-tools;latest"
url = "https://dl.google.com/android/repository/commandlinetools-linux-{version}_latest.zip"
sha256 = "${OLD}"

[[toolchain]]
name = "platform"
version = "37.0"
latest = "sdk"
package = "platforms;android-{version}"

[[toolchain]]
name = "ndk"
version = "29.0.14206865"
latest = "sdk"
package = "ndk;{version}"

[[toolchain]]
name = "gradle"
version = "9.7.1"
latest = "github"
repo = "gradle/gradle"
url = "https://services.gradle.org/distributions/gradle-{version}-bin.zip"
sha256 = "${OLD}"

[[toolchain]]
name = "swift"
version = "6.3.3"
latest = "swift"
`;

// Google's repository lists previews beside stable releases; only channel-0 is stable.
const sdkXml = ({ ndk = '29.0.14206865', tools = '15859902', platform = '37.1', buildTools = '37.0.0' } = {}) => `<?xml version="1.0"?>
<sdk:sdk-repository>
  <channel id="channel-0">stable</channel>
  <remotePackage path="cmdline-tools;latest">
    <channelRef ref="channel-0"/>
    <archives>
      <archive>
        <complete>
          <url>commandlinetools-linux-${tools}_latest.zip</url>
        </complete>
        <host-os>linux</host-os>
      </archive>
      <archive>
        <complete>
          <url>commandlinetools-mac_arm64-99999999_latest.zip</url>
        </complete>
      </archive>
    </archives>
  </remotePackage>
  <remotePackage path="cmdline-tools;14.0-alpha01">
    <channelRef ref="channel-2"/>
    <archives><archive><complete><url>commandlinetools-linux-99999999_latest.zip</url></complete></archive></archives>
  </remotePackage>
  <remotePackage path="platforms;android-37.0">
    <channelRef ref="channel-0"/>
  </remotePackage>
  <remotePackage path="platforms;android-${platform}">
    <channelRef ref="channel-0"/>
  </remotePackage>
  <remotePackage path="build-tools;${buildTools}">
    <channelRef ref="channel-0"/>
  </remotePackage>
  <remotePackage path="platforms;android-37.2-beta3">
    <channelRef ref="channel-0"/>
  </remotePackage>
  <remotePackage path="platforms;android-CANARY">
    <channelRef ref="channel-0"/>
  </remotePackage>
  <remotePackage path="ndk;${ndk}">
    <channelRef ref="channel-0"/>
  </remotePackage>
  <remotePackage path="ndk;31.0.1">
    <channelRef ref="channel-1"/>
  </remotePackage>
</sdk:sdk-repository>
`;

const swiftJson = (names) => JSON.stringify(names.map((name) => ({ name, platforms: [{ name: 'Fedora 41' }] })), null, 2);

test('toolchain entries are each listed with their upstream and never rewritten', () => {
  const w = world({ yaziTag: 'v26.9.1', kakSha: KAK_OLD, file: FILE + TOOLCHAIN });
  w.serve(SDK, sdkXml({ ndk: '30.0.16248370' }));
  w.serve(SWIFT, swiftJson(['6.3.2', '6.3.3', '6.4.1']));
  writeFileSync(join(w.fix, 'gh/gradle_gradle'), 'v9.8.2\n');
  const before = w.read();
  const r = w.bump();
  assert.equal(r.status, 0, r.stderr);
  assert.equal(r.stdout, [
    'all pins current',
    'toolchain cmdline-tools 15859902 is current',
    'toolchain platform 37.0, upstream 37.1 (by hand)',
    'toolchain ndk 29.0.14206865, upstream 30.0.16248370 (by hand)',
    'toolchain gradle 9.7.1, upstream 9.8.2 (by hand)',
    'toolchain swift 6.3.3, upstream 6.4.1 (by hand)',
    '',
  ].join('\n'));
  assert.equal(w.read(), before);
});

test('a toolchain entry whose upstream cannot be read is named and bump exits 1', () => {
  const w = world({ yaziTag: 'v26.10.0', kakSha: KAK_OLD, file: FILE + TOOLCHAIN });
  w.serve(SWIFT, swiftJson(['6.3.3']));
  writeFileSync(join(w.fix, 'gh/gradle_gradle'), 'v9.7.1\n');
  const r = w.bump();
  assert.equal(r.status, 1);
  assert.match(r.stderr, /dots bump: cmdline-tools: could not read Google's SDK repository/);
  assert.match(r.stdout, /^yazi 26\.9\.1 → 26\.10\.0\n/);
  assert.match(r.stdout, /^toolchain gradle 9\.7\.1 is current$/m);
});

// A release tag is text its repo's owner controls, so one that is not a plain version cannot reach the terminal or versions.toml.
test('a pin whose upstream answers with a control character, a quote or an & is left alone, named, and exits 1', () => {
  for (const tag of ['v9.9\u001b[2J', 'v9.9‮1', 'v9.9"x', 'v9.9&x']) {
    const w = world({ yaziTag: tag, kakSha: KAK_OLD });
    const before = w.read();
    const r = w.bump();
    assert.equal(r.status, 1, JSON.stringify(tag));
    assert.equal(r.stdout, '', JSON.stringify(tag));
    assert.match(r.stderr, /^dots bump: yazi: sxyazi\/yazi answered something that is not a version$/m, JSON.stringify(tag));
    assert.equal(w.read(), before, JSON.stringify(tag));
  }
});
