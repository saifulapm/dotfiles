// The yt-dlp pin: both arches carry a url and a sha256, and its script renders for aarch64 and installs the one binary.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, readFileSync, realpathSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const repo = new URL('../../', import.meta.url).pathname;
const versions = readFileSync(join(repo, 'versions.toml'), 'utf8');
const block = versions.split(/^\[\[pin\]\]$/m).find((b) => /^name = "yt-dlp"$/m.test(b));
const key = (k) => block.match(new RegExp(`^${k.replace('.', '\\.')} = "([^"]*)"$`, 'm'))?.[1];

function render(template) {
  const home = realpathSync(mkdtempSync(join(tmpdir(), 'dots-pin-ytdlp-')));
  const r = spawnSync('chezmoi', ['--config', join(home, 'none.toml'), '--source', repo, 'execute-template'], {
    input: template, encoding: 'utf8', env: { PATH: process.env.PATH, HOME: home },
  });
  assert.equal(r.status, 0, r.stderr);
  return r.stdout;
}

test('the pin names both arches by release url and sha256', () => {
  assert.equal(key('version'), '2026.10.26');
  assert.equal(key('check'), 'yt-dlp --version');
  assert.equal(key('url.aarch64'), 'https://github.com/yt-dlp/yt-dlp/releases/download/{version}/yt-dlp_linux_aarch64');
  assert.equal(key('url.x86_64'), 'https://github.com/yt-dlp/yt-dlp/releases/download/{version}/yt-dlp_linux');
  assert.match(key('sha256.aarch64'), /^[0-9a-f]{64}$/);
  assert.match(key('sha256.x86_64'), /^[0-9a-f]{64}$/);
});

test('pin.sh renders the aarch64 binary for the pin', () => {
  const out = render('{{ template "pin.sh" (dict "chezmoi" (dict "arch" "arm64" "workingTree" .chezmoi.workingTree) "name" "yt-dlp") }}');
  assert.match(out, /^pin_url="https:\/\/github\.com\/yt-dlp\/yt-dlp\/releases\/download\/2026\.10\.26\/yt-dlp_linux_aarch64"$/m);
  assert.match(out, new RegExp(`^pin_sha256="${key('sha256.aarch64')}"$`, 'm'));
});

test('the pin script installs the binary to ~/.local/bin/yt-dlp on every machine', () => {
  const out = render(readFileSync(join(repo, 'home/.chezmoiscripts/run_onchange_after_29-pin-yt-dlp.sh.tmpl'), 'utf8'));
  assert.match(out, /^binary=\$\(pin_fetch\)$/m);
  assert.match(out, /^install -D -m 0755 "\$binary" "\$HOME\/\.local\/bin\/yt-dlp"$/m);
});
