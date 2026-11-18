// The verdict for each speed budget; bin/dots-bench gathers the numbers and runs this as a CLI.

// idle RSS is 200 MiB (#7S2JD316, #KSH3FVWD): GL reads 172 MiB, no lever reached 150 without costing real memory, the picker's specimens add 3-7 MiB, and by m24 every start read 194-198.
export const BUDGETS = { firstFrameMs: 150, rssMiB: 200, coldMs: 50, warmMs: 16, timers: 1, switchMs: 300, idleCpu: 0.07, appFirstFrameMs: 500, appRssMiB: 250, appLeft: 0, morphMaxMs: 36, morphP95Ms: 12, morphSwitchMaxMs: 36, morphSwitchP95Ms: 12, controlColdMs: 50, controlWarmMs: 16, morphControlMaxMs: 36, morphControlP95Ms: 12, notifsColdMs: 50, notifsWarmMs: 16, chatColdMs: 50, chatWarmMs: 16 };

// The measured baseline of every row that has one (mem fact 76XT47G6, just bench at d77a9e69).
export const BASELINE = { firstFrameMs: 170, rssMiB: 204, coldMs: 38, warmMs: 3, schemesColdMs: 35, schemesWarmMs: 16, passColdMs: 3, filesColdMs: 11, switchMs: 114, idleCpu: 0.13 };

// The run-to-run spread a row may add to its baseline.
export const SPREAD = { firstFrameMs: 10, rssMiB: 0, coldMs: 17, warmMs: 17, schemesColdMs: 17, schemesWarmMs: 17, passColdMs: 17, filesColdMs: 17, switchMs: 17, idleCpu: 0.02 };

// The c mode, pass and files rows answer to the panel's budgets.
const BUDGET_KEY = { schemesColdMs: 'coldMs', schemesWarmMs: 'warmMs', passColdMs: 'coldMs', filesColdMs: 'coldMs' };

// A row inside its budget stays inside it; a row already over its budget may not get worse than its baseline plus the spread.
export function limits(budgets, baseline, spread) {
  const out = {};
  for (const k of Object.keys(baseline)) {
    const budget = budgets[BUDGET_KEY[k] ?? k];
    const cap = Math.round((baseline[k] + spread[k]) * 1e6) / 1e6;
    out[k] = baseline[k] > budget ? cap : Math.min(budget, cap);
  }
  return out;
}

// The longest frame interval and the 95th percentile (nearest rank) of a morph's frame intervals in ms.
export function frameStats(intervalsMs) {
  if (intervalsMs.length === 0) return null;
  const sorted = intervalsMs.slice().sort((a, b) => a - b);
  return { max: sorted[sorted.length - 1], p95: sorted[Math.ceil(0.95 * sorted.length) - 1] };
}

// The gaps between a morph's frames as island state records them, [ms since it began, ...]; the wait for the first frame is an open's time, not a frame's.
export function morphIntervals(frames) {
  const out = [];
  for (let i = 1; i < frames.length; i++) out.push(frames[i][0] - frames[i - 1][0]);
  return out;
}

const line = (name, value, unit, op, limit, ok) =>
  `${name.padEnd(13)} ${`${value} ${unit}`.padEnd(7)} ${op} ${`${limit} ${unit}`.padEnd(8)} ${ok ? 'ok' : 'OVER'}`;

export function report(m, budgets) {
  const b = Object.assign({}, budgets, limits(budgets, BASELINE, SPREAD));
  const morph = (name, s, max = b.morphMaxMs, p95 = b.morphP95Ms) => (s
    ? line(name, `${s.max}/${s.p95}`, 'ms', '≤', `${max}/${p95}`, s.max <= max && s.p95 <= p95)
    : `${name.padEnd(13)} none`);
  // GPU buffers are shmem, so a lever that moves memory out of RSS into them only shows here; reported, not budgeted.
  const cgroup = `${'cgroup mem'.padEnd(13)} ${Math.floor(m.anonShmemKiB / 1024)} MiB`;
  const checks = [
    line('first frame', m.firstFrameMs, 'ms', '≤', b.firstFrameMs, m.firstFrameMs <= b.firstFrameMs),
    // RSS is compared in KiB, so a value just over the budget is not rounded down into it.
    line('idle rss', Math.floor(m.rssKiB / 1024), 'MiB', '≤', b.rssMiB, m.rssKiB <= b.rssMiB * 1024),
    line('panel cold', m.coldMs, 'ms', '≤', b.coldMs, m.coldMs <= b.coldMs),
    line('panel warm', m.warmMs, 'ms', '≤', b.warmMs, m.warmMs <= b.warmMs),
    // The launcher's colorscheme mode, its forty rows and strips, answers to the launcher's budgets; cold is its first open after a start.
    line('c mode cold', m.schemesColdMs, 'ms', '≤', b.schemesColdMs, m.schemesColdMs <= b.schemesColdMs),
    line('c mode warm', m.schemesWarmMs, 'ms', '≤', b.schemesWarmMs, m.schemesWarmMs <= b.schemesWarmMs),
    // Pass's first open after its 30 s unload, which loads it again.
    line('pass cold', m.passColdMs, 'ms', '≤', b.passColdMs, m.passColdMs <= b.passColdMs),
    // The file picker's first open after its 30 s unload, from the request's arrival to its first frame.
    line('files cold', m.filesColdMs, 'ms', '≤', b.filesColdMs, m.filesColdMs <= b.filesColdMs),
    line('timers', m.timers, '', '=', b.timers, m.timers === b.timers),
    line('theme switch', m.switchMs, 'ms', '≤', b.switchMs, m.switchMs <= b.switchMs),
    // Read at rest on the dot paper: m1's 0.02 % plus 0.05.
    line('idle cpu', m.cpu, '%', '≤', b.idleCpu, Number(m.cpu) <= b.idleCpu),
    // Files is an App, its own qs process: a first frame and an RSS of its own, and no process once its window closes.
    line('app 1st frame', m.appFirstFrameMs, 'ms', '≤', b.appFirstFrameMs, m.appFirstFrameMs <= b.appFirstFrameMs),
    line('app open rss', Math.floor(m.appRssKiB / 1024), 'MiB', '≤', b.appRssMiB, m.appRssKiB <= b.appRssMiB * 1024),
    line('app closed', m.appLeft, 'left', '=', b.appLeft, m.appLeft === b.appLeft),
    // Dekho, the second App, answers to the same budgets.
    line('dekho frame', m.dekhoFirstFrameMs, 'ms', '≤', b.appFirstFrameMs, m.dekhoFirstFrameMs <= b.appFirstFrameMs),
    line('dekho rss', Math.floor(m.dekhoRssKiB / 1024), 'MiB', '≤', b.appRssMiB, m.dekhoRssKiB <= b.appRssMiB * 1024),
    line('dekho closed', m.dekhoLeft, 'left', '=', b.appLeft, m.dekhoLeft === b.appLeft),
    // Deen, the third App, too.
    line('deen frame', m.deenFirstFrameMs, 'ms', '≤', b.appFirstFrameMs, m.deenFirstFrameMs <= b.appFirstFrameMs),
    line('deen rss', Math.floor(m.deenRssKiB / 1024), 'MiB', '≤', b.appRssMiB, m.deenRssKiB <= b.appRssMiB * 1024),
    line('deen closed', m.deenLeft, 'left', '=', b.appLeft, m.deenLeft === b.appLeft),
    // The island's morph in and out, from the frame intervals the shell recorded; a morph that was not timed fails.
    morph('morph open', m.morphOpen),
    morph('morph close', m.morphClose),
    // A switch from one surface straight into another is held as an open is: its long gaps are the nested session's jitter, as an open's are.
    morph('morph switch', m.morphSwitch, b.morphSwitchMaxMs, b.morphSwitchP95Ms),
    // The island's open from rest into Control, the clock gliding with it, held as an open is (EM7XTXZB).
    morph('morph control', m.morphControl, b.morphControlMaxMs, b.morphControlP95Ms),
    // Control in the island, new in m103, held to its budgets only (43NSCSQG): cold is the first open after a start, before the warm-up makes it.
    line('control cold', m.controlColdMs, 'ms', '≤', b.controlColdMs, m.controlColdMs <= b.controlColdMs),
    line('control warm', m.controlWarmMs, 'ms', '≤', b.controlWarmMs, m.controlWarmMs <= b.controlWarmMs),
    // The notification centre in the island, new in m104, held to its budgets (6FNG38AQ): cold is the first open after a start.
    line('notifs cold', m.notifsColdMs, 'ms', '≤', b.notifsColdMs, m.notifsColdMs <= b.notifsColdMs),
    line('notifs warm', m.notifsWarmMs, 'ms', '≤', b.notifsWarmMs, m.notifsWarmMs <= b.notifsWarmMs),
    // The AI chat in the island has no baseline, so it is held to its budgets: cold is the first open after its surface unloaded.
    line('chat cold', m.chatColdMs, 'ms', '≤', b.chatColdMs, m.chatColdMs <= b.chatColdMs),
    line('chat warm', m.chatWarmMs, 'ms', '≤', b.chatWarmMs, m.chatWarmMs <= b.chatWarmMs),
  ];
  // Every theme's shaders and effects loaded once; reported, not budgeted.
  const switched = `${'rss switched'.padEnd(13)} ${Math.floor(m.switchedKiB / 1024)} MiB`;
  return { lines: [...checks.slice(0, 2), cgroup, ...checks.slice(2), switched], over: checks.some((l) => l.endsWith('OVER') || l.endsWith(' none')) };
}

// Round the list and back again from start: with three themes that is each of the six ordered pairs once.
export function switchCycle(themes, start) {
  const i = themes.indexOf(start);
  const ahead = themes.slice(i + 1).concat(themes.slice(0, i));
  return ahead.concat([start], ahead.slice().reverse(), [start]);
}

// bin/dots-bench passes island state's morph frames and reads back the longest interval and the p95 of each frame's work, its sixth field (BH6GX53J).
if (process.argv[2] === 'frames' && import.meta.url === `file://${process.argv[1]}`) {
  const frames = JSON.parse(process.argv[3]);
  const gaps = frameStats(morphIntervals(frames));
  const work = frameStats(frames.map((f) => f[5]));
  console.log(gaps && work ? `${gaps.max} ${work.p95}` : '');
  process.exit(0);
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
  const schemesColdMs = Number(process.argv[11]);
  const schemesWarmMs = Number(process.argv[12]);
  const passColdMs = Number(process.argv[13]);
  const filesColdMs = Number(process.argv[14]);
  const [appFirstFrameMs, appRssKiB, appLeft] = process.argv.slice(15, 18).map(Number);
  const [dekhoFirstFrameMs, dekhoRssKiB, dekhoLeft] = process.argv.slice(18, 21).map(Number);
  const [deenFirstFrameMs, deenRssKiB, deenLeft] = process.argv.slice(21, 24).map(Number);
  const pair = (a) => (a.length === 2 ? { max: Number(a[0]), p95: Number(a[1]) } : null);
  const morphOpen = pair(process.argv.slice(24, 26));
  const morphClose = pair(process.argv.slice(26, 28));
  const morphSwitch = pair(process.argv.slice(28, 30));
  const controlColdMs = Number(process.argv[30]);
  const controlWarmMs = Number(process.argv[31]);
  const morphControl = pair(process.argv.slice(32, 34));
  const notifsColdMs = Number(process.argv[34]);
  const notifsWarmMs = Number(process.argv[35]);
  const chatColdMs = Number(process.argv[36]);
  const chatWarmMs = Number(process.argv[37]);
  const env = (k, d) => (process.env[k] ? Number(process.env[k]) : d);
  const r = report({ firstFrameMs, rssKiB, coldMs, warmMs, timers, switchMs, switchedKiB, anonShmemKiB, schemesColdMs, schemesWarmMs, passColdMs, filesColdMs, appFirstFrameMs, appRssKiB, appLeft, dekhoFirstFrameMs, dekhoRssKiB, dekhoLeft, deenFirstFrameMs, deenRssKiB, deenLeft, morphOpen, morphClose, morphSwitch, controlColdMs, controlWarmMs, morphControl, notifsColdMs, notifsWarmMs, chatColdMs, chatWarmMs, cpu: process.argv[7] }, {
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
    morphMaxMs: env('DOTS_BUDGET_MORPH_MAX_MS', BUDGETS.morphMaxMs),
    morphP95Ms: env('DOTS_BUDGET_MORPH_P95_MS', BUDGETS.morphP95Ms),
    morphSwitchMaxMs: env('DOTS_BUDGET_MORPH_SWITCH_MAX_MS', BUDGETS.morphSwitchMaxMs),
    morphSwitchP95Ms: env('DOTS_BUDGET_MORPH_SWITCH_P95_MS', BUDGETS.morphSwitchP95Ms),
    controlColdMs: env('DOTS_BUDGET_CONTROL_COLD_MS', BUDGETS.controlColdMs),
    controlWarmMs: env('DOTS_BUDGET_CONTROL_WARM_MS', BUDGETS.controlWarmMs),
    morphControlMaxMs: env('DOTS_BUDGET_MORPH_CONTROL_MAX_MS', BUDGETS.morphControlMaxMs),
    morphControlP95Ms: env('DOTS_BUDGET_MORPH_CONTROL_P95_MS', BUDGETS.morphControlP95Ms),
    notifsColdMs: env('DOTS_BUDGET_NOTIFS_COLD_MS', BUDGETS.notifsColdMs),
    notifsWarmMs: env('DOTS_BUDGET_NOTIFS_WARM_MS', BUDGETS.notifsWarmMs),
    chatColdMs: env('DOTS_BUDGET_CHAT_COLD_MS', BUDGETS.chatColdMs),
    chatWarmMs: env('DOTS_BUDGET_CHAT_WARM_MS', BUDGETS.chatWarmMs),
  });
  console.log(r.lines.join('\n'));
  process.exit(r.over ? 1 : 0);
}
