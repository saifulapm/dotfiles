// The verdict for each speed budget; bin/dots-bench gathers the numbers and runs this as a CLI.

// idle RSS stays 180 MiB until Saiful answers #PYS215Y3: GL reads 172 MiB, and no lever reached 150 without costing real memory.
export const BUDGETS = { firstFrameMs: 150, rssMiB: 180, coldMs: 50, warmMs: 16, timers: 1, switchMs: 300, idleCpu: 0.07 };

const line = (name, value, unit, op, limit, ok) =>
  `${name.padEnd(13)} ${`${value} ${unit}`.padEnd(7)} ${op} ${`${limit} ${unit}`.padEnd(8)} ${ok ? 'ok' : 'OVER'}`;

export function report(m, b) {
  const checks = [
    line('first frame', m.firstFrameMs, 'ms', '≤', b.firstFrameMs, m.firstFrameMs <= b.firstFrameMs),
    // RSS is compared in KiB, so a value just over the budget is not rounded down into it.
    line('idle rss', Math.floor(m.rssKiB / 1024), 'MiB', '≤', b.rssMiB, m.rssKiB <= b.rssMiB * 1024),
    line('panel cold', m.coldMs, 'ms', '≤', b.coldMs, m.coldMs <= b.coldMs),
    line('panel warm', m.warmMs, 'ms', '≤', b.warmMs, m.warmMs <= b.warmMs),
    line('timers', m.timers, '', '=', b.timers, m.timers === b.timers),
    line('theme switch', m.switchMs, 'ms', '≤', b.switchMs, m.switchMs <= b.switchMs),
    // Read with Blueprint on, the theme whose grid paper is the costliest to draw: m1's 0.02 % plus 0.05.
    line('idle cpu', m.cpu, '%', '≤', b.idleCpu, Number(m.cpu) <= b.idleCpu),
  ];
  // Every theme's shaders and effects loaded once; reported, not budgeted.
  const switched = `${'rss switched'.padEnd(13)} ${Math.floor(m.switchedKiB / 1024)} MiB`;
  return { lines: [...checks, switched], over: checks.some((l) => l.endsWith('OVER')) };
}

// Round the list and back again from start: with three themes that is each of the six ordered pairs once.
export function switchCycle(themes, start) {
  const i = themes.indexOf(start);
  const ahead = themes.slice(i + 1).concat(themes.slice(0, i));
  return ahead.concat([start], ahead.slice().reverse(), [start]);
}

if (process.argv[2] === 'cycle' && import.meta.url === `file://${process.argv[1]}`) {
  console.log(switchCycle(process.argv.slice(4), process.argv[3]).join(' '));
  process.exit(0);
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const [firstFrameMs, rssKiB, coldMs, warmMs, timers] = process.argv.slice(2, 7).map(Number);
  const switchMs = Number(process.argv[8]);
  const switchedKiB = Number(process.argv[9]);
  const env = (k, d) => (process.env[k] ? Number(process.env[k]) : d);
  const r = report({ firstFrameMs, rssKiB, coldMs, warmMs, timers, switchMs, switchedKiB, cpu: process.argv[7] }, {
    firstFrameMs: env('DOTS_BUDGET_FIRST_FRAME_MS', BUDGETS.firstFrameMs),
    rssMiB: env('DOTS_BUDGET_RSS_MIB', BUDGETS.rssMiB),
    coldMs: env('DOTS_BUDGET_COLD_MS', BUDGETS.coldMs),
    warmMs: env('DOTS_BUDGET_WARM_MS', BUDGETS.warmMs),
    timers: env('DOTS_BUDGET_TIMERS', BUDGETS.timers),
    switchMs: env('DOTS_BUDGET_SWITCH_MS', BUDGETS.switchMs),
    idleCpu: env('DOTS_BUDGET_IDLE_CPU', BUDGETS.idleCpu),
  });
  console.log(r.lines.join('\n'));
  process.exit(r.over ? 1 : 0);
}
