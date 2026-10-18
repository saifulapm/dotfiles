import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { calc, format } from './calc.mjs';

test('1440 * 1.25 is 1800', () => assert.equal(calc('1440 * 1.25'), 1800));
test('an incomplete expression is null', () => assert.equal(calc('2 +'), null));
test('* binds tighter than +', () => assert.equal(calc('2 + 3 * 4'), 14));
test('parentheses override precedence', () => assert.equal(calc('(2 + 3) * 4'), 20));
test('unary minus', () => {
  assert.equal(calc('-3 + 5'), 2);
  assert.equal(calc('2 * -(1 + 1)'), -4);
});
test('^ is a power and right associative', () => {
  assert.equal(calc('2^10'), 1024);
  assert.equal(calc('2^3^2'), 512);
});
test('% is the remainder', () => assert.equal(calc('10 % 3'), 1));
test('division keeps the fraction', () => assert.equal(calc('1 / 4'), 0.25));
test('garbage, empty input, unbalanced parentheses and 1/0 are null', () => {
  for (const s of ['abc', '', '   ', '(1 + 2', '1 + 2)', '1 2', '1..2', 'process.exit()', '1/0', '2 ** 3'])
    assert.equal(calc(s), null, s);
});
test('format drops float noise to 10 significant digits', () => {
  assert.equal(format(1800.0000000001), '1800');
  assert.equal(format(0.1 + 0.2), '0.3');
  assert.equal(format(1 / 3), '0.3333333333');
});
test('calc.mjs never evaluates strings', () => {
  assert.doesNotMatch(readFileSync(new URL('./calc.mjs', import.meta.url), 'utf8'), /\beval\b|Function/);
});
