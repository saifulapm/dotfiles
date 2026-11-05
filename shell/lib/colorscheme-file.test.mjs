import { test } from 'node:test';
import assert from 'node:assert/strict';
import { schemeTokens } from './colorscheme-file.mjs';

test("a colorscheme's tokens carry its own colours on the one design", () => {
  const t = schemeTokens('rose-pine-dawn');
  assert.equal(t.name, 'rose-pine-dawn');
  assert.equal(t.mode, 'light');
  assert.equal(t.color.surface, '#FAF4ED');
  assert.equal(t.color.paper, '#F2E9E1');
  assert.equal(t.primitive.paper, 'dots');
  assert.equal(t.type.voice, 'plain');
});

test('a name that is no colorscheme throws, naming it', () => {
  assert.throws(() => schemeTokens('blueprint'), /blueprint/);
});
