import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { answerLine, deviceName, parseRequest, promptOf, serviceName, typed } from './bt-pairing.mjs';

const req = (r) => JSON.stringify(r);

test('a request line from dots-bt-agent reads as its kind, device, code and service', () => {
  assert.deepEqual(parseRequest(req({ kind: 'confirm', device: 'Test Keyboard', address: '00:00:00:00:00:05', code: '123456', service: '' })), {
    kind: 'confirm',
    device: 'Test Keyboard',
    address: '00:00:00:00:00:05',
    code: '123456',
    service: '',
  });
});

test('a line that is not a request, or names an unknown kind, is refused', () => {
  for (const line of ['', 'nope', '[]', 'null', req({ kind: 'steal', device: 'X' }), req({ device: 'X' })]) assert.equal(parseRequest(line), null, line);
});

test('a device names itself, so its name is one line without controls or bidi marks, and an empty one is its address', () => {
  assert.equal(parseRequest(req({ kind: 'confirm', device: 'Evil\nNext‮', address: 'AA', code: '123456' })).device, 'Evil Next');
  assert.equal(parseRequest(req({ kind: 'confirm', device: '', address: '00:00:00:00:00:07', code: '123456' })).device, '00:00:00:00:00:07');
});

test('a request whose fields BlueZ would never send is refused, not drawn', () => {
  const ok = { kind: 'confirm', device: 'K', address: 'AA', code: '123456', service: '' };
  const bad = [
    { ...ok, device: '', address: '' },
    { ...ok, device: 42, address: '' },
    { ...ok, code: '12ab34' },
    { ...ok, code: '1234567' },
    { ...ok, kind: 'display', code: '' },
    { ...ok, kind: 'authorize', code: '', service: 'audio? press ↵ to keep sound' },
  ];
  for (const r of bad) assert.equal(parseRequest(req(r)), null, JSON.stringify(r));
  assert.equal(parseRequest(req({ ...ok, code: '' })).code, '');
  assert.equal(parseRequest(req({ ...ok, kind: 'pin', code: '' })).kind, 'pin');
  assert.equal(parseRequest(req({ ...ok, kind: 'authorize', code: '', service: '0000110D-0000-1000-8000-00805F9B34FB' })).kind, 'authorize');
});

test('a long device name is cut to 40 characters, so the code always shows', () => {
  const r = parseRequest(req({ kind: 'confirm', device: 'A'.repeat(248), address: 'AA', code: '123456' }));
  assert.equal(r.device, 'A'.repeat(39) + '…');
  assert.equal(promptOf(r).title, `${'A'.repeat(39)}…`);
});

test('each request kind draws as its own board 7 prompt: glyph, device, detail, a code or a field, and its buttons', () => {
  const p = (r) => promptOf(parseRequest(req(r)));
  assert.deepEqual(p({ kind: 'confirm', device: 'Test Keyboard', code: '123456' }), {
    glyph: 0xf00af,
    title: 'Test Keyboard',
    detail: 'check this code shows on the device',
    code: '123456',
    field: false,
    placeholder: '',
    quiet: 'Reject',
    primary: 'Pair',
  });
  assert.deepEqual(p({ kind: 'confirm', device: 'Test Keyboard', code: '' }), {
    glyph: 0xf00af,
    title: 'Test Keyboard',
    detail: 'wants to pair',
    code: '',
    field: false,
    placeholder: '',
    quiet: 'Reject',
    primary: 'Pair',
  });
  assert.deepEqual(p({ kind: 'display', device: 'Magic Keyboard', code: '654321' }), {
    glyph: 0xf030c,
    title: 'Magic Keyboard',
    detail: 'type this on the device, then Enter',
    code: '654321',
    field: false,
    placeholder: '',
    quiet: 'Cancel',
    primary: '',
  });
  assert.deepEqual(p({ kind: 'pin', device: 'Old Mouse' }), {
    glyph: 0xf00af,
    title: 'Old Mouse',
    detail: 'asks for a PIN',
    code: '',
    field: true,
    placeholder: 'PIN',
    quiet: 'Reject',
    primary: 'Pair',
  });
  assert.deepEqual(p({ kind: 'passkey', device: 'Old Mouse' }), {
    glyph: 0xf00af,
    title: 'Old Mouse',
    detail: 'asks for a passkey',
    code: '',
    field: true,
    placeholder: 'Passkey',
    quiet: 'Reject',
    primary: 'Pair',
  });
  assert.deepEqual(p({ kind: 'authorize', device: 'Test Phone', service: '0000110d-0000-1000-8000-00805f9b34fb' }), {
    glyph: 0xf00af,
    title: 'Test Phone',
    detail: 'wants Audio',
    code: '',
    field: false,
    placeholder: '',
    quiet: 'Deny',
    primary: 'Allow',
  });
});

test('bin/dots-bt-agent rejects an unanswered request after 60 s unless DOTS_BT_AGENT_TIMEOUT_S says otherwise', () => {
  const agent = readFileSync(new URL('../../bin/dots-bt-agent', import.meta.url), 'utf8');
  assert.match(agent, /os\.environ\.get\("DOTS_BT_AGENT_TIMEOUT_S", "60"\)/);
});

test('a service is named by its UUID, and an unknown one by its short or full UUID', () => {
  assert.equal(serviceName('0000111E-0000-1000-8000-00805F9B34FB'), 'Hands-Free');
  assert.equal(serviceName('00001124-0000-1000-8000-00805f9b34fb'), 'Keyboard and mouse');
  assert.equal(serviceName('00001234-0000-1000-8000-00805f9b34fb'), 'service 0x1234');
  assert.equal(serviceName('6e400001-b5a3-f393-e0a9-e50e24dcca9e'), 'service 6e400001-b5a3-f393-e0a9-e50e24dcca9e');
  assert.equal(serviceName('a\nb'), 'service ab');
});

test('a PIN takes up to 16 printable characters, a passkey up to 6 digits', () => {
  assert.equal(typed('pin', '000', '0'), '0000');
  assert.equal(typed('pin', '0000', 'a'), '0000a');
  assert.equal(typed('pin', '0000', '\r'), '0000');
  assert.equal(typed('pin', '0123456789abcdef', 'x'), '0123456789abcdef');
  assert.equal(typed('passkey', '12', '3'), '123');
  assert.equal(typed('passkey', '12', 'a'), '12');
  assert.equal(typed('passkey', '123456', '7'), '123456');
  assert.equal(typed('confirm', '', '1'), '');
});

test('the answer line carries yes or no, and the PIN only for a kind that asks one', () => {
  assert.equal(answerLine('confirm', true, ''), '{"ok":true}\n');
  assert.equal(answerLine('confirm', false, ''), '{"ok":false}\n');
  assert.equal(answerLine('pin', true, '0000'), '{"ok":true,"pin":"0000"}\n');
  assert.equal(answerLine('passkey', true, '1234'), '{"ok":true,"pin":"1234"}\n');
  assert.equal(answerLine('pin', false, '0000'), '{"ok":false}\n');
});

test('the failed toast names a device as the question does', () => {
  assert.equal(deviceName('Evil\nNext\u202e', 'AA'), 'Evil Next');
  assert.equal(deviceName('', '00:00:00:00:00:07'), '00:00:00:00:00:07');
  assert.equal(deviceName('B'.repeat(100), 'AA'), 'B'.repeat(39) + '…');
});
