import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { parseToml } from './toml.mjs';
import { listLook } from './voice.mjs';
import { parseRequest, pinAnswer, CANCEL, ALLOW, DENY, errorLine, cardText } from './pinentry.mjs';

const theme = (name) => parseToml(readFileSync(new URL(`../../themes/${name}/theme.toml`, import.meta.url), 'utf8'));

test("a request line gives its kind and gpg's text, unescaped", () => {
  assert.deepEqual(parseRequest('passphrase\tPlease enter%0A"Saiful <s@x>"%0A100%25 yours\tPassphrase:\tBad Passphrase (try 2 of 3)'), {
    kind: 'passphrase',
    description: 'Please enter\n"Saiful <s@x>"\n100% yours',
    prompt: 'Passphrase:',
    error: 'Bad Passphrase (try 2 of 3)',
  });
  assert.deepEqual(parseRequest('confirm\tAllow?\t\t'), { kind: 'confirm', description: 'Allow?', prompt: '', error: '' });
});

test('escaped UTF-8 decodes to its characters, and an escaped tab stays a tab', () => {
  assert.equal(parseRequest('passphrase\tf%C3%BCr a%09b\t\t').description, 'für a\tb');
  assert.equal(parseRequest('passphrase\tfür\t\t').description, 'für');
});

test('a lone percent or broken UTF-8 still reads, never throwing', () => {
  assert.equal(parseRequest('passphrase\t50% off %ZZ\t\t').description, '50% off %ZZ');
  assert.equal(parseRequest('passphrase\tbad %C3 byte\t\t').description, 'bad Ã byte');
});

test('an empty line, as the pinentry probe sends, or an unknown kind is no request', () => {
  assert.equal(parseRequest(''), null);
  assert.equal(parseRequest('getpin\tx\t\t'), null);
  assert.equal(parseRequest('passphrase\tonly two'), null);
});

// The passphrase goes back to gpg on one Assuan data line, so %, CR, LF and other controls are escaped and the rest passes as UTF-8.
test('a passphrase with %, a newline or non-ASCII reaches gpg intact', () => {
  assert.equal(pinAnswer('p%ss\nwörd\r\x01'), 'D p%25ss%0Awörd%0D%01\nOK\n');
  assert.equal(pinAnswer('plain'), 'D plain\nOK\n');
  const back = pinAnswer('a%b\nc').split('\n')[0].slice(2).replace(/%([0-9A-F]{2})/g, (_, h) => String.fromCharCode(parseInt(h, 16)));
  assert.equal(back, 'a%b\nc');
});

test('cancel, allow and deny are the answers pinentry gives', () => {
  assert.equal(CANCEL, 'ERR 83886179 Operation cancelled\n');
  assert.equal(ALLOW, 'OK\n');
  assert.equal(DENY, 'ERR 83886194 Not confirmed\n');
});

test("gpg's bad-passphrase error reads as the board's line, and other errors pass one-lined", () => {
  assert.equal(errorLine('Bad Passphrase (try 2 of 3)'), 'Bad passphrase · try 2 of 3');
  assert.equal(errorLine('Invalid PIN\nentered'), 'Invalid PIN entered');
  assert.equal(errorLine(''), '');
});

test('the card speaks each theme: its heading and key strip, for a passphrase and for a confirmation', () => {
  const t = (name, kind) => cardText(listLook(theme(name)), kind);
  assert.deepEqual(t('paper', 'passphrase'), { heading: 'PASSPHRASE', keys: [{ key: '↵', word: 'UNLOCK' }, { key: 'ESC', word: 'CANCEL' }] });
  assert.deepEqual(t('artboard', 'passphrase'), { heading: 'Passphrase', keys: [{ key: '↵', word: 'unlock' }, { key: 'esc', word: 'cancel' }] });
  assert.deepEqual(t('blueprint', 'passphrase'), { heading: 'GPG // PASSPHRASE', keys: [{ key: '[↵]', word: 'UNLOCK' }, { key: '[ESC]', word: 'CANCEL' }] });
  assert.deepEqual(t('artboard', 'confirm'), { heading: 'Confirm', keys: [{ key: '↵', word: 'allow' }, { key: 'esc', word: 'deny' }] });
  assert.equal(t('blueprint', 'confirm').heading, 'GPG // CONFIRM');
});
