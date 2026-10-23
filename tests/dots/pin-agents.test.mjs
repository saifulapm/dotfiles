// The amx, workflow and pxy pin scripts against local tarballs and a stub cargo whose binaries only log their arguments, so no run builds or runs the real tools.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { copyFileSync, existsSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const repo = new URL('../../', import.meta.url).pathname;
const BINS = ['amx', 'mem', 'workflow', 'hub', 'pxy'];

// The stub cargo writes every binary a pin may ask for, each appending "<name> <args>" to ~/calls.log.
const CARGO = `#!/bin/sh
echo "cargo RUSTC=$RUSTC" >> "$HOME/calls.log"
while [ $# -gt 0 ]; do [ "$1" = --target-dir ] && t=$2; shift; done
mkdir -p "$t/release"
for b in ${BINS.join(' ')}; do printf '#!/bin/sh\\necho "%s $*" >> "$HOME/calls.log"\\n' "$b" > "$t/release/$b"; chmod +x "$t/release/$b"; done
`;

// files: extra paths inside the tarball's top folder, as { path: text }.
function scratch(files = {}) {
  const root = realpathSync(mkdtempSync(join(tmpdir(), 'dots-pin-agents-')));
  const templates = join(root, 'home/.chezmoitemplates');
  mkdirSync(templates, { recursive: true });
  for (const f of ['lib.sh', 'pin.sh', 'cargo.sh']) copyFileSync(join(repo, 'home/.chezmoitemplates', f), join(templates, f));
  writeFileSync(join(root, '.chezmoiroot'), 'home\n');
  let toml = '';
  for (const name of ['amx', 'workflow', 'pxy']) {
    const top = join(root, 'src', `${name}-1.0`);
    for (const crate of name === 'workflow' ? ['mem', 'workflow', 'hub'] : ['.']) mkdirSync(join(top, crate), { recursive: true });
    for (const [path, text] of Object.entries(files[name] ?? {})) {
      mkdirSync(join(top, path, '..'), { recursive: true });
      writeFileSync(join(top, path), text);
    }
    const tar = join(root, `${name}.tar.gz`);
    assert.equal(spawnSync('tar', ['-czf', tar, '-C', join(root, 'src'), `${name}-1.0`]).status, 0);
    const sum = createHash('sha256').update(readFileSync(tar)).digest('hex');
    toml += `[[pin]]\nname = "${name}"\nversion = "1.0"\nrepo = "x/${name}"\nurl = "file://${tar}"\nsha256 = "${sum}"\n\n`;
  }
  writeFileSync(join(root, 'versions.toml'), toml);
  mkdirSync(join(root, 'stubs'));
  writeFileSync(join(root, 'stubs/cargo'), CARGO, { mode: 0o755 });
  // systemctl is stubbed so no run restarts this machine's real hub or pxy.
  writeFileSync(join(root, 'stubs/systemctl'), '#!/bin/sh\nexit 0\n', { mode: 0o755 });
  return root;
}

function run(root, pin) {
  const env = { PATH: `${root}/stubs:${process.env.PATH}`, HOME: root, DOTS_CARGO: `${root}/stubs/cargo` };
  const script = readFileSync(join(repo, 'home/.chezmoiscripts', pin), 'utf8');
  const rendered = spawnSync('chezmoi', ['--config', join(root, 'none.toml'), '--source', root, 'execute-template'], { input: script, encoding: 'utf8', env });
  assert.equal(rendered.status, 0, rendered.stderr);
  return spawnSync('bash', ['-c', rendered.stdout], { encoding: 'utf8', env });
}

const calls = (root) => (existsSync(join(root, 'calls.log')) ? readFileSync(join(root, 'calls.log'), 'utf8').trim().split('\n') : []);

test('the amx pin runs amx setup twice, once for claude and once for pi with its subagent tool', () => {
  const root = scratch();
  const r = run(root, 'run_onchange_after_26-pin-amx.sh.tmpl');
  assert.equal(r.status, 0, r.stderr);
  assert.deepEqual(calls(root), ['cargo RUSTC=/usr/bin/rustc', 'amx setup claude', 'amx setup pi --subagent']);
});

test('the workflow pin runs workflow install and mem doctor --fix once each', () => {
  const root = scratch();
  const r = run(root, 'run_onchange_after_27-pin-workflow.sh.tmpl');
  assert.equal(r.status, 0, r.stderr);
  assert.deepEqual(calls(root), ['cargo RUSTC=/usr/bin/rustc', 'cargo RUSTC=/usr/bin/rustc', 'cargo RUSTC=/usr/bin/rustc', 'workflow install', 'mem doctor --fix']);
});

// pxy's checkout ships its pi extension with placeholders that pxy launch would fill; the pin fills them from the port this repo configures.
const PI_PXY = 'const baseUrl = "__PXY_BASE_URL__";\nconst bin = "__PXY_BIN__";\n';
function pxyHome(template) {
  const root = scratch({ pxy: { 'contrib/pi-pxy.ts': template } });
  mkdirSync(join(root, '.config/pxy'), { recursive: true });
  writeFileSync(join(root, '.config/pxy/config.toml'), '[server]\nhost = "127.0.0.1"\nport = 4100\n');
  return root;
}

test('the pxy pin writes pi\'s pxy extension with the configured port and the installed binary', () => {
  const root = pxyHome(PI_PXY);
  const r = run(root, 'run_onchange_after_28-pin-pxy.sh.tmpl');
  assert.equal(r.status, 0, r.stderr);
  assert.equal(
    readFileSync(join(root, '.pi/agent/extensions/pxy.ts'), 'utf8'),
    `const baseUrl = "http://127.0.0.1:4100/v1";\nconst bin = "${root}/.local/bin/pxy";\n`,
  );
});

test('a placeholder the pin does not know stops it, naming the placeholder, and writes no extension', () => {
  const root = pxyHome(PI_PXY + 'const key = "__PXY_KEY__";\n');
  const r = run(root, 'run_onchange_after_28-pin-pxy.sh.tmpl');
  assert.notEqual(r.status, 0);
  assert.match(r.stderr, /__PXY_KEY__/);
  assert.equal(existsSync(join(root, '.pi/agent/extensions/pxy.ts')), false);
});

// rustup's cargo and rustc sit ahead of Fedora's on a user's PATH, and would build the pinned commit with a toolchain it never saw.
test('a pin builds with Fedora\'s cargo and rustc even when rustup\'s come first on PATH, and says so', () => {
  const root = scratch();
  mkdirSync(join(root, '.cargo/bin'), { recursive: true });
  for (const tool of ['cargo', 'rustc']) writeFileSync(join(root, '.cargo/bin', tool), `#!/bin/sh\necho "rustup ${tool}" >> "$HOME/calls.log"\nexit 1\n`, { mode: 0o755 });
  const env = { PATH: `${root}/.cargo/bin:${process.env.PATH}`, HOME: root };
  const script = readFileSync(join(repo, 'home/.chezmoiscripts/run_onchange_after_28-pin-pxy.sh.tmpl'), 'utf8');
  const rendered = spawnSync('chezmoi', ['--config', join(root, 'none.toml'), '--source', root, 'execute-template'], { input: script, encoding: 'utf8', env });
  assert.equal(rendered.status, 0, rendered.stderr);
  // The tarball holds no crate, so the real cargo fails; the log line comes first.
  const r = spawnSync('bash', ['-c', rendered.stdout], { encoding: 'utf8', env });
  assert.match(r.stdout, /^dots: pin pxy: building with \/usr\/bin\/cargo and \/usr\/bin\/rustc$/m);
  assert.match(r.stderr, /Cargo\.toml/);
  assert.deepEqual(calls(root), []);
});
