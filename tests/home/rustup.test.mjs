// The apply's rustup step against a stub rustup-init and rustup, on a scratch home.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { existsSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const repo = new URL('../../', import.meta.url).pathname;
const script = readFileSync(join(repo, 'home/.chezmoiscripts/run_onchange_after_19-rustup.sh.tmpl'), 'utf8');

// stub rustup-init logs its arguments and writes a rustup that knows a default toolchain only once installed.
function scratch() {
  const home = realpathSync(mkdtempSync(join(tmpdir(), 'dots-rustup-')));
  mkdirSync(join(home, 'stubs'));
  writeFileSync(join(home, 'stubs/rustup-init'), `#!/bin/sh
echo "rustup-init $*" >> "$HOME/calls.log"
mkdir -p "$HOME/.cargo/bin"
printf '#!/bin/sh\\n[ "$1" = default ] && echo stable-aarch64-unknown-linux-gnu\\n' > "$HOME/.cargo/bin/rustup"
chmod +x "$HOME/.cargo/bin/rustup"
`, { mode: 0o755 });
  return home;
}

function run(home) {
  const env = { PATH: `${home}/stubs:${process.env.PATH}`, HOME: home };
  const rendered = spawnSync('chezmoi', ['--config', join(home, 'none.toml'), '--source', repo, 'execute-template'], { input: script, encoding: 'utf8', env });
  assert.equal(rendered.status, 0, rendered.stderr);
  return spawnSync('bash', ['-c', rendered.stdout], { encoding: 'utf8', env });
}

const calls = (home) => (existsSync(join(home, 'calls.log')) ? readFileSync(join(home, 'calls.log'), 'utf8').trim().split('\n') : []);

test('a machine without rustup gets the stable toolchain per user, and its PATH is left to fish', () => {
  const home = scratch();
  const r = run(home);
  assert.equal(r.status, 0, r.stderr);
  assert.deepEqual(calls(home), ['rustup-init -y --no-modify-path --default-toolchain stable']);
});

// Saiful's machines already have rustup and their own toolchains, which the apply must not touch.
test('a machine whose rustup has a default toolchain is left alone', () => {
  const home = scratch();
  run(home);
  const r = run(home);
  assert.equal(r.status, 0, r.stderr);
  assert.equal(calls(home).length, 1);
});

// The install test keeps ~/.cargo in a volume and ~/.rustup fresh, so a rustup without a toolchain must still get one.
test('a rustup with no default toolchain gets stable', () => {
  const home = scratch();
  mkdirSync(join(home, '.cargo/bin'), { recursive: true });
  writeFileSync(join(home, '.cargo/bin/rustup'), '#!/bin/sh\nexit 1\n', { mode: 0o755 });
  const r = run(home);
  assert.equal(r.status, 0, r.stderr);
  assert.deepEqual(calls(home), ['rustup-init -y --no-modify-path --default-toolchain stable']);
});
