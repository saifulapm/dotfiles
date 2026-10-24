// The verdict for each speed budget; bin/dots-bench gathers the numbers and runs this as a CLI.

// idle RSS is 200 MiB (#7S2JD316, #KSH3FVWD): GL reads 172 MiB, no lever reached 150 without costing real memory, the picker's specimens add 3-7 MiB, and by m24 every start read 194-198.
export const BUDGETS = { firstFrameMs: 150, rssMiB: 200, coldMs: 50, warmMs: 16, timers: 1, switchMs: 300, idleCpu: 0.07, appFirstFrameMs: 500, appRssMiB: 250, appLeft: 0 };

const line = (name, value, unit, op, limit, ok) =>
  `${name.padEnd(13)} ${`${value} ${unit}`.padEnd(7)} ${op} ${`${limit} ${unit}`.padEnd(8)} ${ok ? 'ok' : 'OVER'}`;

export function report(m, b) {
  // GPU buffers are shmem, so a lever that moves memory out of RSS into them only shows here; reported, not budgeted.
  const cgroup = `${'cgroup mem'.padEnd(13)} ${Math.floor(m.anonShmemKiB / 1024)} MiB`;
  const checks = [
    line('first frame', m.firstFrameMs, 'ms', '≤', b.firstFrameMs, m.firstFrameMs <= b.firstFrameMs),
    // RSS is compared in KiB, so a value just over the budget is not rounded down into it.
    line('idle rss', Math.floor(m.rssKiB / 1024), 'MiB', '≤', b.rssMiB, m.rssKiB <= b.rssMiB * 1024),
    line('panel cold', m.coldMs, 'ms', '≤', b.coldMs, m.coldMs <= b.coldMs),
    line('panel warm', m.warmMs, 'ms', '≤', b.warmMs, m.warmMs <= b.warmMs),
    // The theme picker answers to the launcher's budgets.
    line('picker cold', m.pickerColdMs, 'ms', '≤', b.coldMs, m.pickerColdMs <= b.coldMs),
    line('picker warm', m.pickerWarmMs, 'ms', '≤', b.warmMs, m.pickerWarmMs <= b.warmMs),
    // Pass's first open after its 30 s unload, which loads it again.
    line('pass cold', m.passColdMs, 'ms', '≤', b.coldMs, m.passColdMs <= b.coldMs),
    // The file picker's first open after its 30 s unload, from the request's arrival to its first frame.
    line('files cold', m.filesColdMs, 'ms', '≤', b.coldMs, m.filesColdMs <= b.coldMs),
    line('timers', m.timers, '', '=', b.timers, m.timers === b.timers),
    line('theme switch', m.switchMs, 'ms', '≤', b.switchMs, m.switchMs <= b.switchMs),
    // Read with Blueprint on, the theme whose grid paper is the costliest to draw: m1's 0.02 % plus 0.05.
    line('idle cpu', m.cpu, '%', '≤', b.idleCpu, Number(m.cpu) <= b.idleCpu),
    // Files is an App, its own qs process: a first frame and an RSS of its own, and no process once its window closes.
    line('app 1st frame', m.appFirstFrameMs, 'ms', '≤', b.appFirstFrameMs, m.appFirstFrameMs <= b.appFirstFrameMs),
    line('app open rss', Math.floor(m.appRssKiB / 1024), 'MiB', '≤', b.appRssMiB, m.appRssKiB <= b.appRssMiB * 1024),
    line('app closed', m.appLeft, 'left', '=', b.appLeft, m.appLeft === b.appLeft),
    // Dekho, the second App, answers to the same budgets.
    line('dekho frame', m.dekhoFirstFrameMs, 'ms', '≤', b.appFirstFrameMs, m.dekhoFirstFrameMs <= b.appFirstFrameMs),
    line('dekho rss', Math.floor(m.dekhoRssKiB / 1024), 'MiB', '≤', b.appRssMiB, m.dekhoRssKiB <= b.appRssMiB * 1024),
    line('dekho closed', m.dekhoLeft, 'left', '=', b.appLeft, m.dekhoLeft === b.appLeft),
  ];
  // Every theme's shaders and effects loaded once; reported, not budgeted.
  const switched = `${'rss switched'.padEnd(13)} ${Math.floor(m.switchedKiB / 1024)} MiB`;
  return { lines: [...checks.slice(0, 2), cgroup, ...checks.slice(2), switched], over: checks.some((l) => l.endsWith('OVER')) };
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
  const anonShmemKiB = Number(process.argv[10]);
  const pickerColdMs = Number(process.argv[11]);
  const pickerWarmMs = Number(process.argv[12]);
  const passColdMs = Number(process.argv[13]);
  const filesColdMs = Number(process.argv[14]);
  const [appFirstFrameMs, appRssKiB, appLeft] = process.argv.slice(15, 18).map(Number);
  const [dekhoFirstFrameMs, dekhoRssKiB, dekhoLeft] = process.argv.slice(18, 21).map(Number);
  const env = (k, d) => (process.env[k] ? Number(process.env[k]) : d);
  const r = report({ firstFrameMs, rssKiB, coldMs, warmMs, timers, switchMs, switchedKiB, anonShmemKiB, pickerColdMs, pickerWarmMs, passColdMs, filesColdMs, appFirstFrameMs, appRssKiB, appLeft, dekhoFirstFrameMs, dekhoRssKiB, dekhoLeft, cpu: process.argv[7] }, {
    firstFrameMs: env('DOTS_BUDGET_FIRST_FRAME_MS', BUDGETS.firstFrameMs),
    rssMiB: env('DOTS_BUDGET_RSS_MIB', BUDGETS.rssMiB),
    coldMs: env('DOTS_BUDGET_COLD_MS', BUDGETS.coldMs),
    warmMs: env('DOTS_BUDGET_WARM_MS', BUDGETS.warmMs),
    timers: env('DOTS_BUDGET_TIMERS', BUDGETS.timers),
    switchMs: env('DOTS_BUDGET_SWITCH_MS', BUDGETS.switchMs),
    idleCpu: env('DOTS_BUDGET_IDLE_CPU', BUDGETS.idleCpu),
    appFirstFrameMs: env('DOTS_BUDGET_APP_FIRST_FRAME_MS', BUDGETS.appFirstFrameMs),
    appRssMiB: env('DOTS_BUDGET_APP_RSS_MIB', BUDGETS.appRssMiB),
    appLeft: env('DOTS_BUDGET_APP_LEFT', BUDGETS.appLeft),
  });
  console.log(r.lines.join('\n'));
  process.exit(r.over ? 1 : 0);
}
