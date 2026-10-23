// The dev tools mise installs, and the cloudflared tunnel config that goes with the dev alias.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const repo = new URL('../../', import.meta.url).pathname;
const config = readFileSync(join(repo, 'home/dot_config/mise/config.toml'), 'utf8');

test('mise declares pnpm, the shopify cli, cloudflared and goimapnotify', () => {
  assert.match(config, /^"?aqua:pnpm\/pnpm"? = "/m);
  assert.match(config, /^"npm:@shopify\/cli" = "/m);
  assert.match(config, /^"aqua:cloudflare\/cloudflared" = "/m);
  assert.match(config, /^"go:gitlab\.com\/shackra\/goimapnotify\/cmd\/goimapnotify" = "2\.5\.8"/m);
});

// Fedora 44 packages none of these five, so they come as prebuilt binaries from the aqua registry.
test('mise declares sd, television, hurl, ast-grep and usql from aqua, and bun', () => {
  for (const tool of ['chmln/sd', 'alexpasmantier/television', 'Orange-OpenSource/hurl', 'ast-grep/ast-grep', 'xo/usql']) {
    assert.match(config, new RegExp(`^"aqua:${tool}" = "latest"$`, 'm'), tool);
  }
  assert.match(config, /^bun = "latest"$/m);
});

test('the cloudflared dev tunnel config renders with this home for the credentials file', (t) => {
  const home = mkdtempSync(join(tmpdir(), 'dots-cloudflared-'));
  t.after(() => rmSync(home, { recursive: true, force: true }));
  const src = join(repo, 'home/private_dot_cloudflared/config.dev.yaml.tmpl');
  const r = spawnSync('chezmoi', ['execute-template', '--source', join(repo, 'home')], {
    encoding: 'utf8',
    input: readFileSync(src, 'utf8'),
    env: { ...process.env, HOME: home },
  });
  assert.equal(r.status, 0, r.stderr);
  assert.match(r.stdout, /^tunnel: 9340ed70-a135-4ed7-a5d8-d63371d366c9$/m);
  assert.ok(r.stdout.includes(`credentials-file: ${home}/.cloudflared/9340ed70-a135-4ed7-a5d8-d63371d366c9.json\n`));
  assert.match(r.stdout, /hostname: dev\.ecommercestaff\.com\n\s+service: http:\/\/localhost:8000/);
  assert.match(r.stdout, /service: http_status:404/);
});
