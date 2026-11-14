// Kakoune's mail buffers from tests/home/mail-fixtures.mjs's store, against golden/mail-kak.txt, written by kak-mail at 23947802 before its read side moved into bin/mail_engine.py.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fixtureStore, goldenPath, renderAll } from './mail-fixtures.mjs';

test('kak-mail draws every box list and fixture thread as the golden render', (t) => {
  assert.equal(renderAll(fixtureStore(t)), readFileSync(goldenPath, 'utf8'));
});
