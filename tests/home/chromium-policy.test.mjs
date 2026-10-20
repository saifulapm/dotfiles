// The apply's Chromium policy step on a scratch home, writing into a scratch policy dir through DOTS_CHROMIUM_POLICY_DIR.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { existsSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, symlinkSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const repo = new URL('../../', import.meta.url).pathname;
const script = readFileSync(join(repo, 'home/.chezmoiscripts/run_onchange_after_12-chromium-policy.sh.tmpl'), 'utf8');

function apply({ chromium }) {
  const home = realpathSync(mkdtempSync(join(tmpdir(), 'dots-chromium-policy-')));
  mkdirSync(join(home, 'stubs'));
  mkdirSync(join(home, 'policy'));
  if (chromium) writeFileSync(join(home, 'stubs/chromium-browser'), '#!/bin/sh\n', { mode: 0o755 });
  // The stubs dir is the whole PATH, so this machine's own chromium-browser cannot answer for a machine without one.
  for (const tool of ['install', 'id']) symlinkSync(`/usr/bin/${tool}`, join(home, 'stubs', tool));
  const env = { PATH: `${home}/stubs`, HOME: home, DOTS_CHROMIUM_POLICY_DIR: join(home, 'policy') };
  const rendered = spawnSync('chezmoi', ['--config', join(home, 'none.toml'), '--source', repo, 'execute-template'], { input: script, encoding: 'utf8', env: { ...env, PATH: process.env.PATH } });
  assert.equal(rendered.status, 0, rendered.stderr);
  return { r: spawnSync('/bin/bash', ['-c', rendered.stdout], { encoding: 'utf8', env }), policy: join(home, 'policy/extensions.json') };
}

// playwright-cli attach --extension talks to this extension in Saiful's own Chromium.
test('the policy force-installs the Playwright Extension from the Web Store', () => {
  const { r, policy } = apply({ chromium: true });
  assert.equal(r.status, 0, r.stderr);
  assert.deepEqual(JSON.parse(readFileSync(policy, 'utf8')), {
    ExtensionInstallForcelist: ['mmlmfjhmonkocbjadbfplnigmagldckm;https://clients2.google.com/service/update2/crx'],
  });
});

test('a machine without Chromium gets no policy', () => {
  const { r, policy } = apply({ chromium: false });
  assert.equal(r.status, 0, r.stderr);
  assert.equal(existsSync(policy), false);
});
