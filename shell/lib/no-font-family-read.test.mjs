import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';

// A check that reads <id>.font.family reads the face the Text asked for, which passes while a fallback face draws (m67's sans heading under Instrument Serif); <id>.fontInfo.family reads the drawn one.
const shell = new URL('..', import.meta.url).pathname;

// The reads from before this lint, per file: each may only go, and a file that loses one lowers its count here.
const BASELINE = {
  'ControlWifi.qml': 2,
  'DeenDuas.qml': 8,
  'DeenHadith.qml': 5,
  'DeenMemorise.qml': 4,
  'DeenPrayer.qml': 1,
  'DeenRead.qml': 1,
  'DekhoBar.qml': 1,
  'DekhoBrowse.qml': 1,
  'DekhoHome.qml': 1,
  'DekhoPerson.qml': 1,
  'DekhoReleases.qml': 1,
  'DekhoTitle.qml': 1,
  'FilePicker.qml': 1,
  'Island.qml': 4,
  'Launcher.qml': 1,
  'Lock.qml': 1,
  'PolkitPrompt.qml': 1,
  'files.qml': 1,
};

test('no .qml under shell/ reads <id>.font.family beyond its baseline, and the baseline is exact', () => {
  const counts = {};
  for (const f of readdirSync(shell, { recursive: true })) {
    if (!f.endsWith('.qml')) continue;
    const n = (readFileSync(join(shell, f), 'utf8').match(/\b[A-Za-z_]\w*\.font\.family\b/g) || []).length;
    if (n > 0) counts[f] = n;
  }
  assert.deepEqual(counts, BASELINE, 'read fontInfo.family instead; a read that went lowers BASELINE');
});
