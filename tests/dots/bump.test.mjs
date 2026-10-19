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

// gh api repos/<owner>/<name>/<what> --jq <expr>: prints $FIX/gh/<owner>_<name>, or an error body on stdout and exit 1 when <owner>_<name>.fail exists.
const STUB_GH = `#!/bin/sh
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
function world({ yaziTag, kakSha, yaziFails = false }) {
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
  writeFileSync(join(repo, 'versions.toml'), FILE);
  const env = { PATH: stubs + delimiter + process.env.PATH, HOME: join(root, 'home'), FIX: fix };
  return {
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
