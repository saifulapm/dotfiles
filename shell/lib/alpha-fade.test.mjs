import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';

// Qt.alpha(c, a) sets c's alpha to a rather than scaling it, so a fade written with it draws a translucent colour near solid mid-fade (m78, Frost's glass); a fade scales the colour's own alpha instead.
const shell = new URL('..', import.meta.url).pathname;
const FADING = /\b(pose|progress|fade)/i;

// The second argument of each Qt.alpha( call in a line, read to its own closing bracket, so a first argument holding commas or calls is skipped whole.
function alphaArgs(line) {
  const found = [];
  for (let at = line.indexOf('Qt.alpha('); at !== -1; at = line.indexOf('Qt.alpha(', at + 1)) {
    let depth = 0;
    let comma = -1;
    for (let i = at + 'Qt.alpha('.length; i < line.length; i++) {
      const ch = line[i];
      if (ch === '(' || ch === '[') depth++;
      else if ((ch === ')' || ch === ']') && depth > 0) depth--;
      else if (ch === ',' && depth === 0 && comma === -1) comma = i;
      else if (ch === ')' && depth === 0) {
        if (comma !== -1) found.push(line.slice(comma + 1, i).trim());
        break;
      }
    }
  }
  return found;
}

const fades = (line) => alphaArgs(line).some((a) => FADING.test(a));

test('the lint sees a pose, progress or fade as the alpha, and not a fixed alpha after a call', () => {
  assert.ok(fades('color: Qt.alpha(c, pose.fill)'));
  assert.ok(fades('color: Qt.alpha(fn(a, b), card.progress)'));
  assert.ok(fades('color: ok ? Qt.alpha(c.ink, 0.5) : Qt.alpha(c.paper, fadeIn)'));
  assert.ok(!fades('color: Qt.alpha(page.c.paper ?? "white", plain ? 0.62 : 0.72)'));
  assert.ok(!fades('color: Qt.alpha(pose.color, 0.5)'));
  assert.ok(!fades('color: Qt.alpha(c.paper, card.style.wash)'));
});

test('no shell QML fades a colour with Qt.alpha', () => {
  const found = [];
  for (const f of readdirSync(shell, { recursive: true })) {
    if (!f.endsWith('.qml')) continue;
    readFileSync(join(shell, f), 'utf8').split('\n').forEach((l, i) => {
      if (!l.trim().startsWith('//') && fades(l)) found.push(`${f}:${i + 1}: ${l.trim()}`);
    });
  }
  assert.deepEqual(found, [], 'scale the colour\'s own alpha instead');
});
