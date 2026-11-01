import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { parseToml } from './toml.mjs';
import { validateTheme, checkTokens } from './theme.mjs';
import { listLook } from './voice.mjs';
import { accountsLook } from './accounts.mjs';
import { dnsKeys, addKeys } from './dns.mjs';
import { pickerLook } from './themes.mjs';

const shell = (n) => checkTokens(validateTheme(parseToml(readFileSync(new URL(`../../themes/${n}/theme.toml`, import.meta.url), 'utf8'))));

// Every word a panel draws for these tokens, joined, so a mark anywhere shows.
const said = (t) => [
  accountsLook(t).active.text,
  ...dnsKeys(listLook(t)).map((k) => k.key),
  ...addKeys(listLook(t)).map((k) => k.key),
  pickerLook(t).tag(true, false).text,
  pickerLook(t).tag(false, true).text,
].join(' ');

test('Accounts, DNS and the picker say Blueprint\'s words bare in Hi-Fi, and Blueprint keeps its marks', () => {
  const bare = said(shell('hi-fi'));
  assert.doesNotMatch(bare, /[[\]]/);
  assert.match(bare, /^ACTIVE space /);
  assert.equal(said(shell('blueprint')).split(' ').slice(0, 3).join(' '), '[ACTIVE] [space] [1-5]');
});
