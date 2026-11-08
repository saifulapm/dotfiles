// delta and bat take their colours from the terminal's palette, which every colorscheme sets, so a diff or a file reads in the scheme, live, with no fixed backgrounds that would sit as blocks on a clear terminal.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { readFileSync } from 'node:fs';

const repo = new URL('../../', import.meta.url).pathname;
const gitConfig = `${repo}home/dot_config/git/config`;
const get = (key) => spawnSync('git', ['config', '--file', gitConfig, '--get', key], { encoding: 'utf8' }).stdout.trim();

test('delta draws syntax in the ANSI palette and marks a change by colour alone, with no fixed background', () => {
  assert.equal(get('core.pager'), 'delta');
  assert.equal(get('delta.syntax-theme'), 'ansi');
  for (const [key, want] of [['delta.minus-style', 'red'], ['delta.minus-emph-style', 'bold red ul'], ['delta.plus-style', 'green'], ['delta.plus-emph-style', 'bold green ul']]) {
    assert.equal(get(key), want, key);
  }
  const delta = spawnSync('git', ['config', '--file', gitConfig, '--get-regexp', '^delta\\.'], { encoding: 'utf8' }).stdout;
  assert.doesNotMatch(delta, /#[0-9a-f]{3,6}/i, 'no hex colour, which would not follow the scheme');
});

test('bat uses the ANSI theme', () => {
  assert.match(readFileSync(`${repo}home/dot_config/bat/config`, 'utf8'), /^--theme=ansi$/m);
});
