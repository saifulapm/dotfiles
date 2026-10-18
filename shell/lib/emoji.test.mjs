import { test } from 'node:test';
import assert from 'node:assert/strict';
import { parseEmojiTest, emojiRows } from './emoji.mjs';

const sample = `# group: Smileys & Emotion

# subgroup: face-smiling
1F600                                                  ; fully-qualified     # 😀 E1.0 grinning face
263A FE0F                                              ; fully-qualified     # ☺️ E0.6 smiling face
263A                                                   ; unqualified         # ☺ E0.6 smiling face

# group: People & Body
1F44B                                                  ; fully-qualified     # 👋 E0.6 waving hand
1F44B 1F3FB                                            ; fully-qualified     # 👋🏻 E1.0 waving hand: light skin tone
1F3FB                                                  ; component           # 🏻 E1.0 light skin tone
1F9D1 200D 1F9B0                                       ; fully-qualified     # 🧑‍🦰 E12.1 person: red hair
23ED                                                   ; minimally-qualified # ⏭ E0.7 next track button

# group: Travel & Places
1F525                                                  ; fully-qualified     # 🔥 E0.6 fire
`;

test('the parser keeps fully-qualified entries as [emoji, name, group]', () => {
  assert.deepEqual(parseEmojiTest(sample), [
    ['😀', 'grinning face', 'Smileys & Emotion'],
    ['☺️', 'smiling face', 'Smileys & Emotion'],
    ['👋', 'waving hand', 'People & Body'],
    ['🧑‍🦰', 'person: red hair', 'People & Body'],
    ['🔥', 'fire', 'Travel & Places'],
  ]);
});

test('the query fire puts the fire emoji first, titled with its name', () => {
  const list = [
    ['🚒', 'fire engine', 'Travel & Places'],
    ['🔥', 'fire', 'Travel & Places'],
    ['🧯', 'fire extinguisher', 'Objects'],
  ];
  const rows = emojiRows(list, 'fire');
  assert.deepEqual(
    rows.map((r) => r.title),
    ['🔥 fire', '🚒 fire engine', '🧯 fire extinguisher'],
  );
  assert.equal(rows[0].exec[rows[0].exec.length - 1], '🔥');
});

test('the emoji reaches the shell as an argument, never inside the script', () => {
  const [row] = emojiRows([['🔥', 'fire', 'Travel & Places']], 'fire');
  assert.equal(row.exec[0], 'sh');
  assert.ok(!row.exec[2].includes('🔥'));
});
