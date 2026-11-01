import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { parseToml } from './toml.mjs';
import { youtubeLook } from './youtube-look.mjs';
import { hearHint } from './deen-read.mjs';
import { words as memoriseWords } from './deen-memorise.mjs';
import { homeText } from './dekho-home.mjs';
import { browseText } from './dekho-browse.mjs';
import { releasesText } from './dekho-releases.mjs';
import { titleText } from './dekho-title.mjs';
import { barText } from './dekho-playing.mjs';
import { voiced } from './passage.mjs';

// Hi-Fi's tokens as the shell reads them: Blueprint's voice plus the engraved flag.
const blueprint = () => parseToml(readFileSync(new URL('../../themes/blueprint/theme.toml', import.meta.url), 'utf8'));
const hifi = () => {
  const t = blueprint();
  t.type = Object.assign({}, t.type, { engraved: true });
  return t;
};

// Every string in a value, however deep, that holds a square bracket.
const marked = (v) => {
  if (typeof v === 'string') return /[[\]]/.test(v) ? [v] : [];
  if (typeof v === 'function' || v === null || typeof v !== 'object') return [];
  return Object.values(v).flatMap(marked);
};

test("YouTube's look draws Blueprint's words without its marks in Hi-Fi and keeps them in Blueprint", () => {
  const h = youtubeLook(hifi());
  const b = youtubeLook(blueprint());
  const keys = (l, view, ...rest) => l.legend(view, ...rest).map((k) => `${k.key} ${k.word}`);
  const all = (l) => [
    l.legend('search'), l.legend('search', true), l.legend('saved'), l.legend('playlist'), l.legend('search', false, 'sidebar'), l.legend('search', false, 'list', 'playlist'),
    l.pick, l.hint, l.failed, l.confirm.keys, l.retry('no space'),
  ];
  assert.deepEqual(marked(all(h)), []);
  assert.ok(marked(all(b)).length > 10);
  assert.deepEqual([h.hint, h.pick.newKey, h.failed.key, h.retry('no space')], ['/', 'N', '↵', 'DOWNLOAD FAILED · no space · ↵ RETRY']);
  assert.deepEqual([b.hint, b.pick.newKey, b.failed.key, b.retry('no space')], ['[/]', '[N]', '[↵]', 'DOWNLOAD FAILED · no space · [↵] RETRY']);
  assert.ok(keys(h, 'search').includes('D/⇧D DOWNLOAD AUDIO / VIDEO'));
  assert.ok(keys(h, 'playlist').includes('⇧S SHUFFLE'));
  assert.ok(keys(b, 'playlist').includes('[⇧S] SHUFFLE'));
});

test("Deen's read hint, memorise words and the dekho words lose their marks in Hi-Fi only", () => {
  assert.equal(hearHint('bracket', true), '↵ HEAR THIS WORD');
  assert.equal(hearHint('bracket'), '[↵] HEAR THIS WORD');
  const m = memoriseWords('bracket', true);
  assert.deepEqual([m.hintKey, m.badge(true), m.badge(false)], ['SPACE', '2 · REVEALED', '1 · RECALL']);
  assert.deepEqual([memoriseWords('bracket').hintKey, memoriseWords('bracket').badge(true)], ['[SPACE]', '[2 · REVEALED]']);

  const home = homeText('bracket', true);
  assert.deepEqual([home.hint, home.retry], ['/', ['R', 'RETRY']]);
  assert.deepEqual([homeText('bracket').hint, homeText('bracket').retry], ['[/]', ['[R]', 'RETRY']]);

  const browse = browseText('bracket', true);
  assert.deepEqual([browse.prefilled('Nolan'), browse.person], ['PREFILLED FROM NOLAN', 'PERSON']);
  assert.deepEqual([browseText('bracket').prefilled('Nolan'), browseText('bracket').person], ['[PREFILLED FROM NOLAN]', '[PERSON]']);

  assert.equal(releasesText('bracket', true).best, 'BEST');
  assert.equal(releasesText('bracket').best, '[BEST]');
  assert.equal(titleText('bracket', true).nextUp, 'NEXT UP');
  assert.equal(titleText('bracket').nextUp, '[NEXT UP]');
  assert.equal(barText('bracket', true).tag, 'NOW PLAYING');
  assert.equal(barText('bracket').tag, '[NOW PLAYING]');

  for (const v of [m, home, browse, releasesText('bracket', true), titleText('bracket', true), barText('bracket', true)]) {
    assert.deepEqual(marked(v), []);
  }
});

test("a passage's label is bare in Hi-Fi and bracketed in Blueprint", () => {
  assert.deepEqual(voiced('bracket', 'hadith', '1:2', true), { label: 'HADITH', ref: '1:2' });
  assert.deepEqual(voiced('bracket', 'hadith', 'abc 1'), { label: '[HADITH]', ref: 'ABC 1' });
});
