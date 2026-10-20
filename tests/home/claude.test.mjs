// The apply's Claude Code step against a stub curl, on a scratch home whose PATH holds no real claude.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { existsSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const repo = new URL('../../', import.meta.url).pathname;
const script = readFileSync(join(repo, 'home/.chezmoiscripts/run_onchange_after_19-claude.sh.tmpl'), 'utf8');

// The stub curl logs each call and hands back an installer that links a fake claude into ~/.local/bin.
const CURL = `#!/bin/sh
echo "$*" >> "$HOME/curl.log"
printf '%s\\n' 'mkdir -p "$HOME/.local/bin" && printf "#!/bin/sh\\necho 9.9.9\\n" > "$HOME/.local/bin/claude" && chmod +x "$HOME/.local/bin/claude"'
`;

function apply({ hasClaude }) {
  const home = realpathSync(mkdtempSync(join(tmpdir(), 'dots-claude-')));
  mkdirSync(join(home, 'stubs'));
  writeFileSync(join(home, 'stubs/curl'), CURL, { mode: 0o755 });
  if (hasClaude) {
    mkdirSync(join(home, '.local/bin'), { recursive: true });
    writeFileSync(join(home, '.local/bin/claude'), '#!/bin/sh\necho 1.0.0\n', { mode: 0o755 });
  }
  const env = { PATH: `${home}/stubs:/usr/bin:/bin`, HOME: home };
  const rendered = spawnSync('chezmoi', ['--config', join(home, 'none.toml'), '--source', repo, 'execute-template'], { input: script, encoding: 'utf8', env });
  assert.equal(rendered.status, 0, rendered.stderr);
  const r = spawnSync('bash', ['-c', rendered.stdout], { encoding: 'utf8', env });
  const calls = existsSync(join(home, 'curl.log')) ? readFileSync(join(home, 'curl.log'), 'utf8').trim().split('\n') : [];
  return { r, calls, home };
}

test('a machine without claude runs the native installer once', () => {
  const { r, calls, home } = apply({ hasClaude: false });
  assert.equal(r.status, 0, r.stderr);
  assert.deepEqual(calls, ['-fsSL https://claude.ai/install.sh']);
  assert.ok(existsSync(join(home, '.local/bin/claude')));
});

// Claude Code updates through dots update, so an installed one is left as it is.
test('a machine with claude in ~/.local/bin runs the installer 0 times', () => {
  const { r, calls } = apply({ hasClaude: true });
  assert.equal(r.status, 0, r.stderr);
  assert.deepEqual(calls, []);
});
