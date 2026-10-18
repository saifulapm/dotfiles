// Pure pieces of `qs ipc call shell status`, kept here so node can test them.

export function rssKiB(procStatus) {
  const m = /^VmRSS:\s+(\d+) kB$/m.exec(procStatus);
  return m ? Number(m[1]) : 0;
}

// Both count from boot; starttime is in clock ticks of 10 ms (CLK_TCK is 100 on Linux).
export function processAgeMs(uptime, selfStat) {
  const starttime = Number(selfStat.slice(selfStat.lastIndexOf(')') + 2).split(' ')[19]);
  return Math.round(parseFloat(uptime) * 100 - starttime) * 10;
}

export function statusJson({ theme, outputs, loaded, sync, rssKiB, timers, firstFrameMs }) {
  return JSON.stringify({ theme, outputs, loaded, sync, rssKiB, timers, firstFrameMs });
}
