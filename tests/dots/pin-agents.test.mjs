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
  const env = { PATH: `${root}/stubs:${process.env.PATH}`, HOME: root };
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
  assert.deepEqual(calls(root), ['amx setup claude', 'amx setup pi --subagent']);
});

test('the workflow pin runs workflow install and mem doctor --fix once each', () => {
  const root = scratch();
  const r = run(root, 'run_onchange_after_27-pin-workflow.sh.tmpl');
  assert.equal(r.status, 0, r.stderr);
  assert.deepEqual(calls(root), ['workflow install', 'mem doctor --fix']);
});
