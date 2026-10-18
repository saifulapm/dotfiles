// Pure pieces of `qs ipc call shell status`, kept here so node can test them.

export function rssKiB(procStatus) {
  const m = /^VmRSS:\s+(\d+) kB$/m.exec(procStatus);
  return m ? Number(m[1]) : 0;
}

export function statusJson({ theme, outputs, loaded, sync, rssKiB, timers }) {
  return JSON.stringify({ theme, outputs, loaded, sync, rssKiB, timers });
}
