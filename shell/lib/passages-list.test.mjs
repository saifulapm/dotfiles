import { test } from 'node:test';
import assert from 'node:assert/strict';
import { execFile, execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { answer } from './deen.mjs';
import * as P from './passage.mjs';

// The real deen, as the shell calls it; the list is only as good as what deen answers for each line.
const deen = process.env.DOTS_DEEN || 'deen';
const list = readFileSync(new URL('../data/passages.txt', import.meta.url), 'utf8');

const run = (args) => new Promise((resolve) => execFile(deen, args, (err, stdout) => resolve(stdout)));

// A machine whose deen predates deen-data, or has none of its texts yet, answers an ayah with no Bangla pronunciation, or no Bangla at all; the list is checked only against a deen that answers in Bangla, and any other answer fails it.
let skip = false;
try {
  execFileSync('sh', ['-c', `command -v "$0"`, deen], { stdio: 'ignore' });
  const a = answer(await run(['api', 'ayah', '94:6']));
  if (a && a.ayah && a.ayah.ar && !(a.ayah.bn && a.ayah.bn_pron)) skip = `${deen} answers 94:6 with no Bangla pronunciation and meaning, so the list is not checked against it`;
} catch (e) {
  skip = `${deen} is not installed, so the list is not checked against it`;
}

// Each line that would draw wrong, as "line <n> <text>: <why>"; every deen call runs at once, so the check stays in seconds.
async function problems(text, ask) {
  const { entries, bad } = P.parse(text);
  const surahs = await ask(['api', 'surahs']);
  const found = bad.map((b) => `line ${b.line} ${b.text}: ${b.why}`);
  const drawn = await Promise.all(entries.map(async (e) => {
    const args = P.deenArgs(e);
    return P.shape(e, args ? await ask(args) : '', surahs);
  }));
  entries.forEach((e, i) => {
    const d = drawn[i];
    const at = `line ${e.line} ${e.kind} ${e.ref ?? e.author}`;
    if (!d) found.push(`${at}: a drawn line is empty`);
    else if (P.overLimit(d)) found.push(`${at}: ${P.overLimit(d)}`);
    else if (e.kind !== 'quote' && [d.ar, d.bn_pron, d.bn, d.ref].some((l) => /[A-Za-z0-9]/.test(l))) found.push(`${at}: a Latin letter or digit is drawn`);
  });
  return found;
}

test('the list holds the approved entries in order', () => {
  const { entries, bad } = P.parse(list);
  assert.deepEqual(bad, []);
  const of = (kind) => entries.filter((e) => e.kind === kind);
  assert.deepEqual(P.KINDS.map((k) => of(k).length), [30, 30, 30, 102]);
  assert.deepEqual([of('ayah')[0].ref, of('hadith')[0].ref, of('dua')[0].ref], ['94:6', 'bukhari:6807', '1']);
  // 15:9 and bukhari:6807 stand where 49:13 and bukhari:1 were, whose Bangla ran past 280.
  assert.equal(of('ayah')[24].ref, '15:9');
  assert.ok(!entries.some((e) => e.ref === '49:13' || e.ref === 'bukhari:1'));
  assert.deepEqual([of('hadith').filter((e) => e.ref.startsWith('bukhari:')).length, of('hadith').filter((e) => e.ref.startsWith('muslim:')).length], [20, 10]);
  assert.deepEqual(of('quote')[89], { kind: 'quote', text: 'Action is the foundational key to all success.', author: 'Pablo Picasso', line: of('quote')[89].line });
});

test('every entry of the list draws from deen within its limits', { skip }, async () => {
  assert.deepEqual(await problems(list, run), []);
});

// Canned answers, so the check's own failures are tested on every machine.
const FAKE = {
  'api surahs': { surahs: [{ n: 94, en: 'Ash-Sharh', bn: 'সূরা আশ-শারহ' }] },
  'api ayah 94:6': { ayah: { s: 94, a: 6, ar: 'إِنَّ', bn_pron: 'ইন্না', bn: 'নিশ্চয়' } },
  'api ayah 94:5': { ayah: { s: 94, a: 5, ar: 'فَإِنَّ', bn_pron: 'ফাইন্না', bn: 'ক'.repeat(281) } },
  'hadith show muslim:1': { hit: { collection: 'muslim', bn: 'সহীহ মুসলিম', hadith: { n: '1', bn: '' } } },
  'dua show 16': { dua: { id: '16', ar: 'ب'.repeat(281), bn_pron: 'বিসমিল্লা-হি', bn: 'আল্লাহর নামে' } },
  'dua show 75a': { dua: { id: '75a', ar: 'ب', bn_pron: 'বি', bn: 'আল্লাহর নামে' } },
};
const fake = async (args) => JSON.stringify(FAKE[args.join(' ')] ?? {});

test('an entry with a line past 280 characters, an empty hadith, a range of ayat or a Latin letter in its Bangla fails, naming its line', async () => {
  const long = `quote ${'x'.repeat(281)} — Someone`;
  assert.deepEqual(await problems(`ayah 94:6\n${long}\nhadith muslim:1\nayah 94:5-6\nayah 94:5\ndua 16\ndua 75a\n`, fake), [
    'line 4 ayah 94:5-6: not one ayah',
    'line 2 quote Someone: English is 281 characters',
    'line 3 hadith muslim:1: a drawn line is empty',
    'line 5 ayah 94:5: Bangla is 281 characters',
    'line 6 dua 16: Arabic is 281 characters',
    'line 7 dua 75a: a Latin letter or digit is drawn',
  ]);
});
