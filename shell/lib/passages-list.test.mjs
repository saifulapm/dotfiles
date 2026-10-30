import { test } from 'node:test';
import assert from 'node:assert/strict';
import { execFile, execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import * as P from './passage.mjs';

// The real deen, as the shell calls it; the list is only as good as what deen answers for each line.
const deen = process.env.DOTS_DEEN || 'deen';
const list = readFileSync(new URL('../data/passages.txt', import.meta.url), 'utf8');
let missing = false;
try {
  execFileSync('sh', ['-c', `command -v "$0"`, deen], { stdio: 'ignore' });
} catch (e) {
  missing = true;
}
const skip = missing ? `${deen} is not installed, so the list is not checked against it` : false;

const run = (args) => new Promise((resolve) => execFile(deen, args, (err, stdout) => resolve(stdout)));

// Each line that would draw wrong, as "line <n> <text>: <why>"; every deen call runs at once, so the check stays in seconds.
async function problems(text) {
  const { entries, bad } = P.parse(text);
  const surahs = await run(['api', 'surahs']);
  const found = bad.map((b) => `line ${b.line} ${b.text}: ${b.why}`);
  const drawn = await Promise.all(entries.map(async (e) => {
    const args = P.deenArgs(e);
    return P.shape(e, args ? await run(args) : '', surahs);
  }));
  entries.forEach((e, i) => {
    const d = drawn[i];
    const at = `line ${e.line} ${e.kind} ${e.ref ?? e.author}`;
    if (!d) found.push(`${at}: a drawn field is empty`);
    else if (d.en.length > 280) found.push(`${at}: English is ${d.en.length} characters`);
    else if (d.ar.length > 280) found.push(`${at}: Arabic is ${d.ar.length} characters`);
  });
  return found;
}

test('the list holds the approved entries in order', () => {
  const { entries, bad } = P.parse(list);
  assert.deepEqual(bad, []);
  const of = (kind) => entries.filter((e) => e.kind === kind);
  assert.deepEqual(P.KINDS.map((k) => of(k).length), [30, 30, 30, 102]);
  assert.deepEqual([of('ayah')[0].ref, of('hadith')[0].ref, of('dua')[0].ref], ['94:6', 'bukhari:1', '1']);
  assert.deepEqual([of('hadith').filter((e) => e.ref.startsWith('bukhari:')).length, of('hadith').filter((e) => e.ref.startsWith('muslim:')).length], [20, 10]);
  assert.deepEqual(of('quote')[89], { kind: 'quote', text: 'Action is the foundational key to all success.', author: 'Pablo Picasso', line: of('quote')[89].line });
});

test('every entry of the list draws from deen within its limits', { skip }, async () => {
  assert.deepEqual(await problems(list), []);
});

test('an entry past 280 characters, an empty hadith or a range of ayat fails, naming its line', { skip }, async () => {
  const long = `quote ${'x'.repeat(281)} — Someone`;
  assert.deepEqual(await problems(`ayah 94:6\n${long}\nhadith muslim:1\nayah 94:5-6\n`), [
    'line 4 ayah 94:5-6: not one ayah',
    'line 2 quote Someone: English is 281 characters',
    'line 3 hadith muslim:1: a drawn field is empty',
  ]);
});
