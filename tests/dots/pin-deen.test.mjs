// The deen-data and deen pin scripts, run in chezmoi's order against a scratch source: deen is a local tarball with a stub build-data and a stub cargo, deen-data is a tarball a stub gh hands over, so no run reaches the network.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { copyFileSync, existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, realpathSync, statSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const repo = new URL('../../', import.meta.url).pathname;
const scripts = join(repo, 'home/.chezmoiscripts');
const SCRIPTS = ['run_onchange_after_29-pin-deen-data.sh.tmpl', 'run_onchange_after_29-pin-deen.sh.tmpl'];
const sha = (b) => createHash('sha256').update(b).digest('hex');

// build-data logs its sources, then writes each file from them, or fails without writing when FAIL names it.
const BUILD = `#!/bin/sh
echo "build-data $1" >>"$FETCH_LOG"
[ "$FAIL" = build-data ] && exit 1
mkdir -p "$2"
printf '{"bn":"%s"}' "$(cat "$1/quran/ben-abubakrzakaria.json")" >"$2/quran.json"
printf '{}' >"$2/words.json"
printf '{}' >"$2/duas.json"
`;
const CARGO = `#!/bin/sh
while [ $# -gt 0 ]; do [ "$1" = --target-dir ] && t=$2; shift; done
mkdir -p "$t/release" && printf '#!/bin/sh\\necho deen\\n' > "$t/release/deen" && chmod +x "$t/release/deen"
`;
// gh api repos/x/deen-data/tarball/<commit> prints that commit's tarball from $TARBALLS.
const GH = `#!/bin/sh
echo "gh $*" >>"$FETCH_LOG"
cat "$TARBALLS/\${2##*/}.tar.gz"
`;

const ZAKARIA = 'নিশ্চয় কষ্টের সাথেই স্বস্তি আছে।';
const KHAN = 'নিশ্চয় কষ্টের সাথে স্বস্তি রয়েছে।';

// A deen-data commit as GitHub's tarball lays it out, its manifest summing each file; tamper changes a file after it was summed.
function deenData(root, commit, files, tamper = {}) {
  const top = join(root, 'tar', `x-deen-data-${commit}`);
  const manifest = [];
  for (const [path, text] of Object.entries(files)) {
    mkdirSync(join(top, path, '..'), { recursive: true });
    writeFileSync(join(top, path), text);
    manifest.push(`[[file]]\npath = "${path}"\nsha256 = "${sha(text)}"\nupstream = "u"\nupstream_ref = "r"\nlicence = "l"\n`);
  }
  writeFileSync(join(top, 'manifest.toml'), manifest.join('\n'));
  for (const [path, text] of Object.entries(tamper)) writeFileSync(join(top, path), text);
  const tarball = join(root, 'tarballs', `${commit}.tar.gz`);
  assert.equal(spawnSync('tar', ['-czf', tarball, '-C', join(root, 'tar'), `x-deen-data-${commit}`]).status, 0);
  return sha(readFileSync(tarball));
}

const SOURCES = (bn) => ({ 'quran/ben-abubakrzakaria.json': bn, 'words/words.json': '{}', 'duas/hisn.json': '{}' });

// pin(root, commit, sum) points the deen-data pin at a commit; sum defaults to its tarball's.
function source() {
  const root = realpathSync(mkdtempSync(join(tmpdir(), 'dots-pin-deen-')));
  const templates = join(root, 'home/.chezmoitemplates');
  mkdirSync(templates, { recursive: true });
  for (const f of ['lib.sh', 'pin.sh', 'cargo.sh']) copyFileSync(join(repo, 'home/.chezmoitemplates', f), join(templates, f));
  writeFileSync(join(root, '.chezmoiroot'), 'home\n');
  const crate = join(root, 'pkg/deen-abc');
  mkdirSync(join(crate, 'scripts'), { recursive: true });
  writeFileSync(join(crate, 'Cargo.toml'), '[package]\nname = "deen"\n');
  writeFileSync(join(crate, 'scripts/build-data'), BUILD, { mode: 0o755 });
  mkdirSync(join(root, 'tarballs'));
  const tarball = join(root, 'deen-abc.tar.gz');
  assert.equal(spawnSync('tar', ['-czf', tarball, '-C', join(root, 'pkg'), 'deen-abc']).status, 0);
  writeFileSync(join(root, 'deen.pin'), `[[pin]]\nname = "deen"\nversion = "abc"\nrepo = "x/deen"\nurl = "file://${root}/deen-{version}.tar.gz"\nsha256 = "${sha(readFileSync(tarball))}"\n`);
  mkdirSync(join(root, 'stubs'));
  writeFileSync(join(root, 'stubs/cargo'), CARGO, { mode: 0o755 });
  writeFileSync(join(root, 'stubs/gh'), GH, { mode: 0o755 });
  mkdirSync(join(root, '.config/gh'), { recursive: true });
  writeFileSync(join(root, '.config/gh/hosts.yml'), 'github.com:\n    user: x\n');
  return root;
}

function pin(root, commit, sum) {
  writeFileSync(
    join(root, 'versions.toml'),
    `[[pin]]\nname = "deen-data"\nversion = "${commit}"\nrepo = "x/deen-data"\ntrack = "commit"\nfetch = "gh"\n` +
      `url = "https://github.com/x/deen-data/archive/{version}.tar.gz"\nsha256 = "${sum}"\n\n` +
      readFileSync(join(root, 'deen.pin'), 'utf8'),
  );
}

function render(root, name, env = {}) {
  const rendered = spawnSync('chezmoi', ['--config', join(root, 'none.toml'), '--source', root, 'execute-template'], {
    input: readFileSync(join(scripts, name), 'utf8'),
    encoding: 'utf8',
    env: { PATH: process.env.PATH, HOME: root, ...env },
  });
  assert.equal(rendered.status, 0, rendered.stderr);
  return rendered.stdout;
}

// Both scripts in chezmoi's order; a failing one stops the apply, as chezmoi does.
function run(root, env = {}) {
  const out = { status: 0, stdout: '', stderr: '' };
  for (const name of SCRIPTS) {
    const r = spawnSync('bash', ['-c', render(root, name, env)], {
      encoding: 'utf8',
      env: {
        PATH: `${join(root, 'stubs')}:${process.env.PATH}`,
        HOME: root,
        DOTS_CARGO: join(root, 'stubs/cargo'),
        FETCH_LOG: join(root, 'fetch.log'),
        TARBALLS: join(root, 'tarballs'),
        ...env,
      },
    });
    out.stdout += r.stdout;
    out.stderr += r.stderr;
    out.status = r.status;
    if (r.status !== 0) break;
  }
  return out;
}

const data = (root) => join(root, '.local/share/deen');
const sources = (root) => join(root, '.local/share/deen-data');
const bn = (root) => JSON.parse(readFileSync(join(data(root), 'quran.json'), 'utf8')).bn;
const calls = (root) => (existsSync(join(root, 'fetch.log')) ? readFileSync(join(root, 'fetch.log'), 'utf8').trim().split('\n') : []);
const mtimes = (dir) => readdirSync(dir).map((f) => [f, statSync(join(dir, f)).mtimeMs]);

test('the pins build deen, take deen-data through gh and build the data from it', () => {
  const root = source();
  pin(root, 'c1', deenData(root, 'c1', SOURCES(ZAKARIA)));
  const r = run(root);
  assert.equal(r.status, 0, r.stderr);
  assert.equal(spawnSync(join(root, '.local/bin/deen'), { encoding: 'utf8' }).stdout, 'deen\n');
  assert.equal(bn(root), ZAKARIA);
  assert.deepEqual(readdirSync(data(root)).sort(), ['built-from', 'duas.json', 'quran.json', 'words.json']);
  assert.equal(readFileSync(join(sources(root), '.commit'), 'utf8').trim(), 'c1');
  assert.equal(readFileSync(join(sources(root), 'quran/ben-abubakrzakaria.json'), 'utf8'), ZAKARIA);
  assert.deepEqual(calls(root), ['gh api repos/x/deen-data/tarball/c1', `build-data ${sources(root)}`]);
  assert.match(r.stdout, /dots: pin deen-data c1/);
  assert.match(r.stdout, /dots: pin deen abc/);
});

test('a second apply with the same pins downloads and builds nothing', () => {
  const root = source();
  pin(root, 'c1', deenData(root, 'c1', SOURCES(ZAKARIA)));
  assert.equal(run(root).status, 0);
  const before = mtimes(data(root));
  const r = run(root);
  assert.equal(r.status, 0, r.stderr);
  assert.deepEqual(mtimes(data(root)), before);
  assert.equal(calls(root).length, 2);
});

// A machine whose data came from the old upstreams has quran.json and no record of what built it.
test('data built before deen-data, and then a new deen-data pin, are each rebuilt', () => {
  const root = source();
  mkdirSync(data(root), { recursive: true });
  writeFileSync(join(data(root), 'quran.json'), JSON.stringify({ bn: KHAN }));
  pin(root, 'c1', deenData(root, 'c1', SOURCES(ZAKARIA)));
  assert.equal(run(root).status, 0);
  assert.equal(bn(root), ZAKARIA);
  pin(root, 'c2', deenData(root, 'c2', SOURCES(`${ZAKARIA} ২`)));
  const r = run(root);
  assert.equal(r.status, 0, r.stderr);
  assert.equal(bn(root), `${ZAKARIA} ২`);
  assert.equal(readFileSync(join(data(root), 'built-from'), 'utf8').trim(), 'abc c2');
});

test('a file that differs from the manifest stops the apply, names it, and leaves the data as it was', () => {
  const root = source();
  pin(root, 'c1', deenData(root, 'c1', SOURCES(ZAKARIA)));
  assert.equal(run(root).status, 0);
  const before = [mtimes(data(root)), readFileSync(join(sources(root), '.commit'), 'utf8')];
  pin(root, 'c2', deenData(root, 'c2', SOURCES(KHAN), { 'quran/ben-abubakrzakaria.json': `${KHAN}x` }));
  const r = run(root);
  assert.notEqual(r.status, 0);
  assert.match(r.stderr, /deen-data: quran\/ben-abubakrzakaria\.json does not match manifest\.toml/);
  assert.deepEqual([mtimes(data(root)), readFileSync(join(sources(root), '.commit'), 'utf8')], before);
  assert.equal(bn(root), ZAKARIA);
  assert.doesNotMatch(r.stdout, /dots: pin deen-data c2/);
});

// GitHub builds a tarball on request, so the same commit can come back as other bytes: the pin's own sum says so, before any file is checked.
test('a tarball whose sum is not the pinned one stops the apply at that check', () => {
  const root = source();
  deenData(root, 'c1', SOURCES(ZAKARIA));
  pin(root, 'c1', '0'.repeat(64));
  const r = run(root);
  assert.notEqual(r.status, 0);
  assert.match(r.stderr, /pin deen-data: sha256 of .* is not 0{64}/);
  assert.equal(existsSync(sources(root)), false);
});

test('with no GitHub login the apply warns, builds deen and goes on without the data', () => {
  const root = source();
  pin(root, 'c1', deenData(root, 'c1', SOURCES(ZAKARIA)));
  const empty = mkdtempSync(join(tmpdir(), 'dots-gh-'));
  const r = run(root, { GH_CONFIG_DIR: empty });
  assert.equal(r.status, 0, r.stderr);
  assert.match(r.stdout, /^deen-data: not logged in to GitHub \(gh auth login\), Bangla data skipped$/m);
  assert.equal(spawnSync(join(root, '.local/bin/deen'), { encoding: 'utf8' }).stdout, 'deen\n');
  assert.equal(existsSync(join(data(root), 'quran.json')), false);
  assert.deepEqual(calls(root), []);
});

// chezmoi reruns a script only when its rendered text changes, so the deen script's text carries what its data is built from.
test('a new deen-data pin or a new login changes both scripts as chezmoi sees them', () => {
  const root = source();
  pin(root, 'c1', deenData(root, 'c1', SOURCES(ZAKARIA)));
  const empty = mkdtempSync(join(tmpdir(), 'dots-gh-'));
  const first = SCRIPTS.map((s) => render(root, s));
  SCRIPTS.forEach((s, i) => assert.notEqual(render(root, s, { GH_CONFIG_DIR: empty }), first[i], s));
  pin(root, 'c2', deenData(root, 'c2', SOURCES(ZAKARIA)));
  SCRIPTS.forEach((s, i) => assert.notEqual(render(root, s), first[i], s));
});

test('a failed build stops the apply, names the script and keeps the old data', () => {
  const root = source();
  pin(root, 'c1', deenData(root, 'c1', SOURCES(ZAKARIA)));
  assert.equal(run(root).status, 0);
  pin(root, 'c2', deenData(root, 'c2', SOURCES(KHAN)));
  const r = run(root, { FAIL: 'build-data' });
  assert.notEqual(r.status, 0);
  assert.match(r.stderr, /pin deen: scripts\/build-data failed/);
  assert.equal(bn(root), ZAKARIA);
  assert.equal(readFileSync(join(data(root), 'built-from'), 'utf8').trim(), 'abc c1');
  assert.doesNotMatch(r.stdout, /dots: pin deen abc/);
});

// The hadith corpus is the App's to download on its first open (#33H4T7C0), so the pin never fetches it.
test('the pins leave the hadith corpus alone', () => {
  const root = source();
  pin(root, 'c1', deenData(root, 'c1', SOURCES(ZAKARIA)));
  assert.equal(run(root).status, 0);
  assert.equal(existsSync(join(data(root), 'hadith')), false);
});
