import { test } from 'node:test';
import assert from 'node:assert/strict';
import { springCurve, ease } from './island.mjs';
import { hostMotion, rowFade, bottomRadius, REST, CONCAVE, surfaceYields, modeOf, shownNotification } from './island-host.mjs';

test('the island opens and switches on springCurve(260, 0.7, 30), 362 ms where the old open took 611', () => {
  const m = hostMotion();
  assert.deepEqual(m.open, springCurve(260, 0.7, 30));
  assert.equal(m.open.ms, 362);
  assert.equal(springCurve(260, 0.7).ms, 611);
});

test('the open overshoots by about 4.6% and ends at rest', () => {
  const peak = Math.max(...hostMotion().open.points);
  assert.ok(peak > 1.04 && peak < 1.05, `peak ${peak}`);
  assert.equal(ease(hostMotion().open.points, 1), 1);
});

test('the close is a 120 ms ease-out: fast at first, never past rest', () => {
  const { close } = hostMotion();
  assert.equal(close.ms, 120);
  assert.deepEqual([close.points[0], close.points[60]], [0, 1]);
  assert.ok(close.points.every((y, i) => y <= 1 && (i === 0 || y >= close.points[i - 1])));
  assert.ok(ease(close.points, 0.25) > 0.5, 'an ease-out covers most of the way in its first quarter');
});

test('the outgoing content fades over 80 ms, and the incoming comes in over 200 ms after 60, as each island part swaps', () => {
  assert.equal(hostMotion().outMs, 80);
  assert.deepEqual(hostMotion().swap, { kind: 'rise', inMs: 200, outMs: 80, delay: 60, rise: 6 });
});

test('on a close the incoming content fades in over the close itself, with no delay or rise, so the island settles inside 200 ms', () => {
  assert.deepEqual(hostMotion().closeSwap, { kind: 'rise', inMs: 120, outMs: 80, delay: 0, rise: 0 });
});

test('row n of the incoming content fades in from 60 + 18 n ms for 200 ms, rising 6 px', () => {
  assert.deepEqual(rowFade(0), { delay: 60, ms: 200, rise: 6 });
  assert.deepEqual(rowFade(1), { delay: 78, ms: 200, rise: 6 });
  assert.deepEqual(rowFade(5), { delay: 150, ms: 200, rise: 6 });
});

// 496AQ7DS: rows past the tenth (n = 9) come in with it, so a long surface settles by 422 ms, a frame inside behaviour 4's 450.
test('the stagger stops at the tenth row, so every row is in by 422 ms', () => {
  assert.deepEqual(rowFade(9), rowFade(40));
  assert.notDeepEqual(rowFade(8), rowFade(9));
  const last = rowFade(200);
  assert.equal(last.delay + last.ms, 422);
});

test('the island rests at 176 x 34 with 12 px concave corners', () => {
  assert.deepEqual(REST, { width: 176, height: 34 });
  assert.equal(CONCAVE, 12);
});

test('the bottom corners are 14 px on a one-line island and 20 px on anything taller', () => {
  assert.equal(bottomRadius(34), 14);
  assert.equal(bottomRadius(35), 20);
  assert.equal(bottomRadius(640), 20);
});

test('the bottom radius follows the same progress as the box, from 14 to 20 and back', () => {
  assert.equal(bottomRadius(34, 600, 0), 14);
  assert.equal(bottomRadius(34, 600, 1), 20);
  assert.equal(bottomRadius(34, 600, 0.5), 17);
  assert.equal(bottomRadius(600, 34, 1), 14);
});

const note = { key: 'n1', summary: 'hi' };

// PCGX7JPJ: until the waiting dot, a live state that arrives while a surface is open takes the island.
test('a live state that arrives while a surface is open takes the island', () => {
  assert.equal(surfaceYields({}, { notification: note }), true);
  assert.equal(surfaceYields({}, { osd: { kind: 'volume', value: 40 } }), true);
  assert.equal(surfaceYields({}, { toast: 'Copied' }), true);
  assert.equal(surfaceYields({}, { question: { id: 'Q1' } }), true);
});

test('a state already live when the surface opened keeps it open', () => {
  const playing = { title: 'T', artist: 'A' };
  assert.equal(surfaceYields({ playing, recording: '00:12' }, { playing: { title: 'U', artist: 'A' }, recording: '00:13' }), false);
  assert.equal(surfaceYields({ notification: note }, { notification: note }), false);
  assert.equal(surfaceYields({}, {}), false);
});

test('a second notification or a new question arriving over the first takes the island', () => {
  assert.equal(surfaceYields({ notification: note }, { notification: { key: 'n2', summary: 'again' } }), true);
  assert.equal(surfaceYields({ question: { id: 'Q1' } }, { question: { id: 'Q2' } }), true);
});

test('a state going away keeps the surface open', () => {
  assert.equal(surfaceYields({ notification: note, osd: { kind: 'volume', value: 40 } }, {}), false);
});

test('an open surface outranks every slot, a question and a lease card among them; with none open the slots rank as before', () => {
  const all = { question: { id: 'Q1', text: 'q', options: [] }, leaseCard: true, notification: note, osd: { kind: 'volume', value: 40 } };
  assert.equal(modeOf('cheatsheet', all), 'surface');
  assert.equal(modeOf(null, all), 'question');
  assert.equal(modeOf(null, { notification: note }), 'notification');
  assert.equal(modeOf(null, {}), 'rest');
});

// 61SHXHG7: niri can only black out a whole layer from a cast, which would black out the whole output, so the island keeps notifications to itself instead.
test('while a screen is shared the island shows no notification, and shows it again once the share ends', () => {
  const share = [{ kind: 'PipeWire', session: 1 }];
  assert.equal(shownNotification(note, share), null);
  assert.equal(shownNotification(note, null), note);
  assert.equal(shownNotification(null, null), null);
  assert.equal(modeOf(null, { notification: shownNotification(note, share), sharing: share }), 'sharing');
});
