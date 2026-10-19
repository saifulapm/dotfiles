// The verdict for a soak's RSS samples; bin/dots-soak writes the CSV and runs this as a CLI.
import { readFileSync } from 'node:fs';

const LIMIT_MIB = 5;

// Same column layout as bench's lines, but the failing word is FAIL.
const line = (name, value, unit, op, limit, ok) =>
  `${name.padEnd(13)} ${`${value} ${unit}`.padEnd(7)} ${op} ${`${limit} ${unit}`.padEnd(8)} ${ok ? 'ok' : 'FAIL'}`;

// Drift is the last minute's RSS against minute 5's, after the shell has warmed up.
export function verdict(csv) {
  const rows = csv.trim().split('\n').slice(1).map((l) => l.split(',').map(Number));
  const base = rows.find(([m]) => m === 5);
  if (!base) throw new Error('the CSV has no minute 5 row');
  const driftKiB = rows[rows.length - 1][1] - base[1];
  const ok = driftKiB <= LIMIT_MIB * 1024;
  const driftMiB = Math.floor(driftKiB / 1024);
  return { driftMiB, ok, line: line('rss drift', driftMiB, 'MiB', '≤', LIMIT_MIB, ok) };
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const v = verdict(readFileSync(process.argv[2], 'utf8'));
  console.log(v.line);
  process.exit(v.ok ? 0 : 1);
}
