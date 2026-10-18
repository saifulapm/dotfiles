import { test } from 'node:test';
import assert from 'node:assert/strict';
import { rssKiB, statusJson } from './status.mjs';

const PROC = 'Name:\tqs\nVmPeak:\t  900000 kB\nVmRSS:\t   78416 kB\nRssAnon:\t   40000 kB\n';

test('reads VmRSS in KiB out of /proc/self/status', () => {
  assert.equal(rssKiB(PROC), 78416);
});

test('a status text without VmRSS reads as 0', () => {
  assert.equal(rssKiB('Name:\tqs\n'), 0);
});

test('status is JSON with every field the health check reads', () => {
  const json = statusJson({ theme: 'paper', outputs: ['winit'], loaded: [], sync: {}, rssKiB: 78416, timers: 0 });
  assert.equal(json, '{"theme":"paper","outputs":["winit"],"loaded":[],"sync":{},"rssKiB":78416,"timers":0}');
});
