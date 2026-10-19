// fc-match with the repo's fontconfig as the only user config, against the fonts installed on this machine.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { cpSync, mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const confd = new URL('../../home/dot_config/fontconfig/conf.d', import.meta.url).pathname;

function fcMatch(t, ...args) {
  const dir = mkdtempSync(join(tmpdir(), 'dots-fonts-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  cpSync(confd, join(dir, 'fontconfig/conf.d'), { recursive: true });
  return execFileSync('fc-match', args, { env: { ...process.env, XDG_CONFIG_HOME: dir }, encoding: 'utf8' }).trim();
}

test('each generic and each named family answers with the font we chose', (t) => {
  const asks = ['monospace', 'sans-serif', 'serif', 'system-ui', 'ui-monospace', 'Maple Mono', 'Instrument Serif', 'Symbols Nerd Font Mono'];
  // fc-match reads a '-' as the start of a size, so it is escaped; apps pass the name whole.
  const got = asks.map((f) => fcMatch(t, '-f', '%{family[0]}', f.replaceAll('-', '\\-')));
  assert.deepEqual(got, ['Maple Mono', 'Noto Sans', 'Noto Serif', 'Noto Sans', 'Maple Mono', 'Maple Mono', 'Instrument Serif', 'Symbols Nerd Font Mono']);
});

test('Bangla text falls back to Noto Sans Bengali, even from monospace', (t) => {
  assert.equal(fcMatch(t, '-f', '%{family[0]}', 'monospace:lang=bn'), 'Noto Sans Bengali');
  assert.equal(fcMatch(t, '-f', '%{family[0]}', 'sans-serif:charset=0995'), 'Noto Sans Bengali');
});

test('text draws unhinted, in greyscale', (t) => {
  assert.equal(fcMatch(t, '-f', '%{hinting} %{hintstyle} %{rgba} %{antialias}', 'monospace'), 'False 0 5 True');
});
