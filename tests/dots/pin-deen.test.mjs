// The deen pin script against a scratch source whose deen pin is a local tarball with stub fetch scripts, and a stub cargo, so no run reaches the network.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { copyFileSync, existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, realpathSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const repo = new URL('../../', import.meta.url).pathname;
const SCRIPT = readFileSync(join(repo, 'home/.chezmoiscripts/run_onchange_after_29-pin-deen.sh.tmpl'), 'utf8');

// Each stub fetch script logs its name and prints a JSON object, or fails when FAIL names it.
const FETCH = (name) => `#!/bin/sh
echo ${name} >>"$FETCH_LOG"
[ "$FAIL" = ${name} ] && { echo partial; exit 1; }
echo '{"from":"${name}"}'
`;
const CARGO = `#!/bin/sh
while [ $# -gt 0 ]; do [ "$1" = --target-dir ] && t=$2; shift; done
mkdir -p "$t/release" && printf '#!/bin/sh\\necho deen\\n' > "$t/release/deen" && chmod +x "$t/release/deen"
`;

function source() {
  const root = realpathSync(mkdtempSync(join(tmpdir(), 'dots-pin-deen-')));
  const templates = join(root, 'home/.chezmoitemplates');
  mkdirSync(templates, { recursive: true });
  for (const f of ['lib.sh', 'pin.sh', 'cargo.sh']) copyFileSync(join(repo, 'home/.chezmoitemplates', f), join(templates, f));
  writeFileSync(join(root, '.chezmoiroot'), 'home\n');
  const crate = join(root, 'pkg/deen-abc');
  mkdirSync(join(crate, 'scripts'), { recursive: true });
  writeFileSync(join(crate, 'Cargo.toml'), '[package]\nname = "deen"\n');
  for (const s of ['fetch-data', 'fetch-words', 'fetch-duas']) writeFileSync(join(crate, 'scripts', s), FETCH(s), { mode: 0o755 });
  const tarball = join(root, 'deen-abc.tar.gz');
  assert.equal(spawnSync('tar', ['-czf', tarball, '-C', join(root, 'pkg'), 'deen-abc']).status, 0);
  const sum = createHash('sha256').update(readFileSync(tarball)).digest('hex');
  writeFileSync(join(root, 'versions.toml'), `[[pin]]\nname = "deen"\nversion = "abc"\nrepo = "x/deen"\nurl = "file://${root}/deen-{version}.tar.gz"\nsha256 = "${sum}"\n`);
  mkdirSync(join(root, 'stubs'));
  writeFileSync(join(root, 'stubs/cargo'), CARGO, { mode: 0o755 });
  return root;
}

function run(root, env = {}) {
  const rendered = spawnSync('chezmoi', ['--config', join(root, 'none.toml'), '--source', root, 'execute-template'], {
    input: SCRIPT,
    encoding: 'utf8',
    env: { PATH: process.env.PATH, HOME: root },
  });
  assert.equal(rendered.status, 0, rendered.stderr);
  return spawnSync('bash', ['-c', rendered.stdout], {
    encoding: 'utf8',
    env: { PATH: process.env.PATH, HOME: root, DOTS_CARGO: join(root, 'stubs/cargo'), FETCH_LOG: join(root, 'fetch.log'), ...env },
  });
}

const data = (root) => join(root, '.local/share/deen');
const fetched = (root) => (existsSync(join(root, 'fetch.log')) ? readFileSync(join(root, 'fetch.log'), 'utf8').trim().split('\n') : []);

test('the pin builds deen and fetches the Quran text, its word meanings and Hisn al-Muslim', () => {
  const root = source();
  const r = run(root);
  assert.equal(r.status, 0, r.stderr);
  assert.equal(spawnSync(join(root, '.local/bin/deen'), { encoding: 'utf8' }).stdout, 'deen\n');
  assert.deepEqual(JSON.parse(readFileSync(join(data(root), 'quran.json'), 'utf8')), { from: 'fetch-data' });
  assert.deepEqual(JSON.parse(readFileSync(join(data(root), 'words.json'), 'utf8')), { from: 'fetch-words' });
  assert.deepEqual(JSON.parse(readFileSync(join(data(root), 'duas.json'), 'utf8')), { from: 'fetch-duas' });
  assert.match(r.stdout, /dots: pin deen abc/);
});

test('a second apply fetches nothing that is already there', () => {
  const root = source();
  assert.equal(run(root).status, 0);
  const r = run(root);
  assert.equal(r.status, 0, r.stderr);
  assert.deepEqual(fetched(root), ['fetch-data', 'fetch-words', 'fetch-duas']);
});

// The hadith corpus is the App's to download on its first open (#33H4T7C0), so the pin never fetches it.
test('the pin leaves the hadith corpus alone', () => {
  const root = source();
  assert.equal(run(root).status, 0);
  assert.deepEqual(readdirSync(data(root)).sort(), ['duas.json', 'quran.json', 'words.json']);
});

test('a failed fetch stops the apply, names the script and leaves no partial file', () => {
  const root = source();
  const r = run(root, { FAIL: 'fetch-words' });
  assert.notEqual(r.status, 0);
  assert.match(r.stderr, /pin deen: scripts\/fetch-words failed/);
  assert.deepEqual(readdirSync(data(root)).sort(), ['quran.json']);
  assert.doesNotMatch(r.stdout, /dots: pin deen abc/);
});
