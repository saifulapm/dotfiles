// The chezmoi theme script renders the saved colorscheme, and bin/dots-dev can seed the nested session with one.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

const repo = new URL('../../', import.meta.url).pathname;
const read = (f) => readFileSync(join(repo, f), 'utf8');

test('the theme script hashes the colorschemes and renders the saved one', () => {
  const script = read('home/.chezmoiscripts/run_onchange_after_10-theme.sh.tmpl');
  assert.match(script, /^# theme sources hash:.*"colorschemes\/\*"/m);
  for (const f of ['colorscheme\\*\\.mjs', 'render-out\\.mjs', 'theme\\.mjs', 'apps\\.mjs', 'toml\\.mjs']) assert.match(script, new RegExp(`shell/lib/${f}`), f);
  assert.match(script, /^node .*colorscheme-render\.mjs" \| quote \}\} --saved \|\| die/m);
  assert.doesNotMatch(script, /paper|theme-render\.mjs/);
});

test('dots-dev renders DOTS_DEV_SCHEME with the colorscheme render and keeps the legacy default otherwise', () => {
  const dev = read('bin/dots-dev');
  assert.match(dev, /colorscheme-render\.mjs" "\$DOTS_DEV_SCHEME"/);
  assert.match(dev, /theme-render\.mjs" "\$\{DOTS_DEV_THEME:-paper\}"/);
});
