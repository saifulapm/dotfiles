import { test } from 'node:test';
import assert from 'node:assert/strict';
import { processAgeMs, rssKiB, statusJson } from './status.mjs';

const PROC = 'Name:\tqs\nVmPeak:\t  900000 kB\nVmRSS:\t   78416 kB\nRssAnon:\t   40000 kB\n';

test('reads VmRSS in KiB out of /proc/self/status', () => {
  assert.equal(rssKiB(PROC), 78416);
});

test('a status text without VmRSS reads as 0', () => {
  assert.equal(rssKiB('Name:\tqs\n'), 0);
});

test('status is JSON with every field the health check reads', () => {
  const json = statusJson({ theme: 'paper', outputs: ['winit'], loaded: [], sync: {}, rssKiB: 78416, timers: 0, firstFrameMs: 92, transition: 'zoom' });
  assert.equal(json, '{"theme":"paper","outputs":["winit"],"loaded":[],"sync":{},"rssKiB":78416,"timers":0,"firstFrameMs":92,"transition":"zoom"}');
});

// Field 22 is starttime in clock ticks since boot; the comm in field 2 may hold spaces and parens.
const SELF_STAT = '4242 (qs (x) y) S 1 4242 4242 0 -1 4194560 900 0 0 0 5 3 0 0 20 0 9 0 1709200 905000000 19000';

test('process age is /proc/uptime minus starttime, in ms', () => {
  assert.equal(processAgeMs('17093.27 124775.83\n', SELF_STAT), 1270);
});
