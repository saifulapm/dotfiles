// The Antigravity CLI: bin/dots-agy against a stub curl that serves a manifest and a release archive, the apply step that runs it, the settings it pins, and its own updater switched off.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, realpathSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, relative } from 'node:path';

const repo = new URL('../../', import.meta.url).pathname;
const MANIFEST = 'https://antigravity-cli-auto-updater-974169037036.us-central1.run.app/manifests';
const ARCHIVE = 'https://storage.googleapis.com/antigravity-public/antigravity-cli/1.5.19/cli.tar.gz';

// A scratch home whose stub curl serves a 1.5.19 manifest and an archive holding a fake antigravity binary. opts.arch: what uname -m says; opts.installed: the version a fake ~/.local/bin/agy already prints; opts.badSha: the manifest's sha512 matches nothing.
function scratch(t, opts = {}) {
  const home = realpathSync(mkdtempSync(join(tmpdir(), 'dots-agy-')));
  t.after(() => rmSync(home, { recursive: true, force: true }));
  const stubs = join(home, 'stubs');
  const pkg = join(home, 'pkg');
  mkdirSync(stubs);
  mkdirSync(pkg);
  writeFileSync(join(pkg, 'antigravity'), '#!/bin/sh\necho 1.5.19\n', { mode: 0o755 });
  assert.equal(spawnSync('tar', ['-czf', join(stubs, 'cli.tar.gz'), '-C', pkg, 'antigravity']).status, 0);
  rmSync(pkg, { recursive: true });
  const sha = opts.badSha ? '0'.repeat(128) : createHash('sha512').update(readFileSync(join(stubs, 'cli.tar.gz'))).digest('hex');
  writeFileSync(join(stubs, 'manifest.json'), JSON.stringify({ version: '1.5.19', url: ARCHIVE, sha512: sha }));
  writeFileSync(
    join(stubs, 'curl'),
    `#!/bin/sh\necho "$*" >> "$HOME/curl.log"\nif [ "$2" = -o ]; then cp ${stubs}/cli.tar.gz "$3"; else cat ${stubs}/manifest.json; fi\n`,
    { mode: 0o755 },
  );
  writeFileSync(join(stubs, 'uname'), `#!/bin/sh\n[ "$1" = -m ] && echo ${opts.arch ?? 'aarch64'} || exec /usr/bin/uname "$@"\n`, { mode: 0o755 });
  if (opts.installed) {
    mkdirSync(join(home, '.local/bin'), { recursive: true });
    writeFileSync(join(home, '.local/bin/agy'), `#!/bin/sh\necho ${opts.installed}\n`, { mode: 0o755 });
  }
  const env = { PATH: `${stubs}:/usr/bin:/bin`, HOME: home, TMPDIR: tmpdir() };
  return { home, env };
}

const calls = (home) => (existsSync(join(home, 'curl.log')) ? readFileSync(join(home, 'curl.log'), 'utf8').trim().split('\n') : []);
const agy = (s) => spawnSync(join(repo, 'bin/dots-agy'), [], { encoding: 'utf8', env: s.env });
const version = (home) => spawnSync(join(home, '.local/bin/agy'), ['--version'], { encoding: 'utf8' }).stdout.trim();
// Every file under home but the stubs and the curl log, so a profile the installer would have touched shows up.
const files = (home) =>
  readdirSync(home, { recursive: true, withFileTypes: true })
    .filter((d) => d.isFile())
    .map((d) => relative(home, join(d.parentPath, d.name)))
    .filter((f) => !f.startsWith('stubs/') && f !== 'curl.log')
    .sort();

test('a machine without agy gets the manifest\'s build in ~/.local/bin and no other file', (t) => {
  const s = scratch(t);
  writeFileSync(join(s.home, '.bashrc'), '# seed\n');
  const r = agy(s);
  assert.equal(r.status, 0, r.stderr);
  const [manifest, archive, ...rest] = calls(s.home);
  assert.equal(manifest, `-fsSL ${MANIFEST}/linux_arm64.json`);
  assert.match(archive, new RegExp(`^-fsSL -o \\S+ ${ARCHIVE}$`));
  assert.deepEqual(rest, []);
  assert.equal(version(s.home), '1.5.19');
  assert.deepEqual(files(s.home), ['.bashrc', '.local/bin/agy']);
  assert.equal(readFileSync(join(s.home, '.bashrc'), 'utf8'), '# seed\n');
});

test('an x86_64 machine reads the amd64 manifest', (t) => {
  const s = scratch(t, { arch: 'x86_64' });
  assert.equal(agy(s).status, 0);
  assert.equal(calls(s.home)[0], `-fsSL ${MANIFEST}/linux_amd64.json`);
});

test('an agy already at the manifest\'s version is left as it is, with no download', (t) => {
  const s = scratch(t, { installed: '1.5.19' });
  const before = readFileSync(join(s.home, '.local/bin/agy'), 'utf8');
  const r = agy(s);
  assert.equal(r.status, 0, r.stderr);
  assert.equal(calls(s.home).length, 1);
  assert.equal(readFileSync(join(s.home, '.local/bin/agy'), 'utf8'), before);
});

test('an older agy is replaced by the manifest\'s build', (t) => {
  const s = scratch(t, { installed: '1.5.16' });
  const r = agy(s);
  assert.equal(r.status, 0, r.stderr);
  assert.equal(version(s.home), '1.5.19');
});

test('an archive that does not match the manifest\'s sha512 fails and leaves the old agy', (t) => {
  const s = scratch(t, { installed: '1.5.16', badSha: true });
  const r = agy(s);
  assert.notEqual(r.status, 0);
  assert.match(r.stderr, /sha512/);
  assert.equal(version(s.home), '1.5.16');
  assert.deepEqual(files(s.home), ['.local/bin/agy']);
});

function apply(s) {
  const script = readFileSync(join(repo, 'home/.chezmoiscripts/run_onchange_after_19-antigravity.sh.tmpl'), 'utf8');
  const rendered = spawnSync('chezmoi', ['--config', join(s.home, 'none.toml'), '--source', repo, 'execute-template'], { input: script, encoding: 'utf8', env: s.env });
  assert.equal(rendered.status, 0, rendered.stderr);
  return spawnSync('bash', ['-c', rendered.stdout], { encoding: 'utf8', env: s.env });
}

test('the apply installs agy on a machine without it', (t) => {
  const s = scratch(t);
  const r = apply(s);
  assert.equal(r.status, 0, r.stderr);
  assert.equal(version(s.home), '1.5.19');
});

// agy updates through dots update, so the apply leaves an installed one alone, even an old one.
test('the apply fetches nothing on a machine that has agy', (t) => {
  const s = scratch(t, { installed: '1.5.16' });
  const r = apply(s);
  assert.equal(r.status, 0, r.stderr);
  assert.deepEqual(calls(s.home), []);
});

const settings = (input) =>
  spawnSync('bash', [join(repo, 'home/dot_gemini/antigravity-cli/modify_private_settings.json')], { input, encoding: 'utf8' });

// colorScheme "terminal" draws agy in foot's palette, so it follows every dots colorscheme; agy's other keys stay as agy left them.
test('settings pin colorScheme to terminal and keep the keys agy wrote', () => {
  const r = settings(JSON.stringify({ colorScheme: 'dark', trustedWorkspaces: ['/home/x/Codes'], editorMode: 'vim' }));
  assert.equal(r.status, 0, r.stderr);
  assert.deepEqual(JSON.parse(r.stdout), { colorScheme: 'terminal', trustedWorkspaces: ['/home/x/Codes'], editorMode: 'vim' });
});

test('settings on a machine where agy never ran hold only the colour scheme', () => {
  const r = settings('');
  assert.equal(r.status, 0, r.stderr);
  assert.deepEqual(JSON.parse(r.stdout), { colorScheme: 'terminal' });
});

test('agy\'s own updater is off for the desktop\'s sessions and for fish over SSH', () => {
  assert.match(readFileSync(join(repo, 'home/dot_config/environment.d/85-agy.conf'), 'utf8'), /^AGY_CLI_DISABLE_AUTO_UPDATE=true$/m);
  const home = realpathSync(mkdtempSync(join(tmpdir(), 'dots-agy-')));
  const fish = spawnSync('fish', ['--no-config', '-c', `source ${join(repo, 'home/dot_config/fish/config.fish')}; echo $AGY_CLI_DISABLE_AUTO_UPDATE`], {
    encoding: 'utf8',
    env: { PATH: process.env.PATH, HOME: home, XDG_STATE_HOME: join(home, 'state') },
  });
  rmSync(home, { recursive: true, force: true });
  assert.equal(fish.stdout.trim(), 'true');
});
