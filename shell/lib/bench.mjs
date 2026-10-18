// The verdict for each speed budget; bin/dots-bench gathers the numbers and runs this as a CLI.
export const BUDGETS = { firstFrameMs: 150, rssMiB: 150, coldMs: 50, warmMs: 16, timers: 1 };

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
  ];
  return { lines: [...checks, `${'idle cpu'.padEnd(13)} ${m.cpu} %`], over: checks.some((l) => l.endsWith('OVER')) };
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const [firstFrameMs, rssKiB, coldMs, warmMs, timers] = process.argv.slice(2, 7).map(Number);
  const env = (k, d) => (process.env[k] ? Number(process.env[k]) : d);
  const r = report({ firstFrameMs, rssKiB, coldMs, warmMs, timers, cpu: process.argv[7] }, {
    firstFrameMs: env('DOTS_BUDGET_FIRST_FRAME_MS', BUDGETS.firstFrameMs),
    rssMiB: env('DOTS_BUDGET_RSS_MIB', BUDGETS.rssMiB),
    coldMs: env('DOTS_BUDGET_COLD_MS', BUDGETS.coldMs),
    warmMs: env('DOTS_BUDGET_WARM_MS', BUDGETS.warmMs),
    timers: env('DOTS_BUDGET_TIMERS', BUDGETS.timers),
  });
  console.log(r.lines.join('\n'));
  process.exit(r.over ? 1 : 0);
}
