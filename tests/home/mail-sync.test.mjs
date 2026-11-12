// bin/mail-sync tells the desktop once when three fetches in a row failed; every run here uses fake mail tools and a scratch HOME.
import { test } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { chmodSync, existsSync, mkdirSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";

const script = resolve(import.meta.dirname, "../../bin/mail-sync");

const hhmm = () => {
  const d = new Date();
  return `${String(d.getHours()).padStart(2, "0")}:${String(d.getMinutes()).padStart(2, "0")}`;
};

function fake(dir, name, body) {
  const path = join(dir, name);
  writeFileSync(path, `#!/usr/bin/env bash\n${body}\n`);
  chmodSync(path, 0o755);
}

function rig() {
  const root = mkdtempSync(join(tmpdir(), "mail-sync-"));
  const bin = join(root, "bin");
  const home = join(root, "home");
  const state = join(root, "state");
  mkdirSync(bin);
  mkdirSync(home);
  mkdirSync(state);
  const notified = join(root, "notified");
  const notmuchCalls = join(root, "notmuch-calls");
  const mbsyncCalls = join(root, "mbsync-calls");
  const verdict = join(root, "verdict");
  const dropped = join(root, "dropped");
  fake(bin, "notify-send", `printf '%s\\n' "$*" >>"${notified}"`);
  fake(bin, "notmuch", `echo "$*" >>"${notmuchCalls}"`);
  fake(
    bin,
    "mbsync",
    `echo run >>"${mbsyncCalls}"\n[ "$(cat "${verdict}")" = fail ] && { echo m >"${dropped}"; exit 1; }\nexit 0`,
  );
  const env = {
    ...process.env,
    HOME: home,
    XDG_STATE_HOME: state,
    PATH: `${bin}:${process.env.PATH}`,
  };
  const run = (outcome) => {
    writeFileSync(verdict, outcome);
    const result = spawnSync(script, ["--quiet"], { env, encoding: "utf8" });
    assert.equal(result.status, 0, result.stderr);
  };
  const calls = () => (existsSync(notified) ? readFileSync(notified, "utf8").trim().split("\n") : []);
  return { run, calls, state, env, notmuchCalls, dropped };
}

test("three failed fetches after a good one notify once with the good run's time", () => {
  const r = rig();
  const before = hhmm();
  r.run("ok");
  const after = hhmm();
  r.run("fail");
  r.run("fail");
  assert.deepEqual(r.calls(), []);
  r.run("fail");
  const calls = r.calls();
  assert.equal(calls.length, 1);
  const allowed = new Set([before, after].map((t) => `-a Mail -i mail-unread Mail has not synced since ${t}`));
  assert.ok(allowed.has(calls[0]), calls[0]);
});

test("later failures in the same streak stay quiet", () => {
  const r = rig();
  r.run("ok");
  for (let i = 0; i < 5; i++) r.run("fail");
  assert.equal(r.calls().length, 1);
});

test("a failure between two good runs sends nothing", () => {
  const r = rig();
  r.run("ok");
  r.run("fail");
  r.run("ok");
  assert.deepEqual(r.calls(), []);
});

test("a good run after the notice lets three more failures notify again", () => {
  const r = rig();
  r.run("ok");
  for (let i = 0; i < 3; i++) r.run("fail");
  r.run("ok");
  for (let i = 0; i < 3; i++) r.run("fail");
  assert.equal(r.calls().length, 2);
});

test("with no good run on record the first failure's time is used", () => {
  const r = rig();
  const before = hhmm();
  for (let i = 0; i < 3; i++) r.run("fail");
  const after = hhmm();
  const calls = r.calls();
  assert.equal(calls.length, 1);
  assert.match(calls[0], new RegExp(`Mail has not synced since (${before}|${after})$`));
});

test("a failed fetch still indexes what landed", () => {
  const r = rig();
  r.run("fail");
  assert.ok(existsSync(r.dropped));
  assert.match(readFileSync(r.notmuchCalls, "utf8"), /^new --quiet$/m);
});

test("a run that finds the lock held changes no streak state", () => {
  const r = rig();
  r.run("ok");
  r.run("fail");
  r.run("fail");
  const snapshot = () =>
    spawnSync("bash", ["-c", `cd "${r.state}/hey-mail" && for f in $(ls | grep -v -e sync.log -e sync.lock); do echo $f; cat $f; done`], {
      encoding: "utf8",
    }).stdout;
  const held = snapshot();
  assert.notEqual(held, "");
  const result = spawnSync(
    "flock",
    ["-n", `${r.state}/hey-mail/sync.lock`, script, "--quiet"],
    { env: r.env, encoding: "utf8" },
  );
  assert.equal(result.status, 0, result.stderr);
  assert.equal(snapshot(), held);
  assert.deepEqual(r.calls(), []);
});
