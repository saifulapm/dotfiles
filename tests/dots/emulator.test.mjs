// dots-emulator against stubs first on PATH: adb lists the emulators that have a file under emulators/ and answers each one's console and getprop, systemd-run "boots" one for the AVD it was given, systemctl keeps units as files, and sleep finishes a pending boot, so no test waits.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { chmodSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const bin = new URL('../../bin/dots-emulator', import.meta.url).pathname;

const STUBS = {
  // The real one prints its AVD's name, then OK, and a real adb shell reads its stdin to the end.
  adb: `case "$*" in
  devices) echo "List of devices attached"; for f in "$S"/emulators/*; do [ -e "$f" ] && printf '%s\\tdevice\\n' "\${f##*/}"; done; echo ;;
  "-s "*" emu avd name") [ -e "$S/emulators/$2" ] || exit 1; cat "$S/emulators/$2"; echo OK ;;
  "-s "*" emu kill") echo "kill $2" >>"$S/adb.log"; rm -f "$S/emulators/$2" "$S/booted/$2" ;;
  "-s "*" shell getprop sys.boot_completed") cat >>"$S/stdin.log"; [ -e "$S/booted/$2" ] && echo 1 ;;
  *) echo "adb stub: $*" >&2; exit 1 ;;
esac
`,
  systemctl: `[ "$1" = --user ] || exit 1
shift
echo "$*" >>"$S/systemctl.log"
case $1 in
  is-active) if [ -e "$S/active/$2" ]; then echo active; else echo inactive; exit 3; fi ;;
  stop) [ -e "$S/active/$2" ] && { s=$(cat "$S/active/$2"); rm -f "$S/active/$2" "$S/emulators/$s" "$S/booted/$s"; } ;;
  reset-failed) ;;
  *) exit 1 ;;
esac
exit 0
`,
  // systemd-run --user --unit=<name> --collect --quiet <emulator> -avd <avd> ...
  'systemd-run': `printf '%s\\n' "$*" >>"$S/systemd-run.log"
unit= avd=
while (($#)); do
  case $1 in --unit=*) unit=\${1#--unit=}.service ;; -avd) avd=$2 ;; esac
  shift
done
[ "$(cat "$S/mode" 2>/dev/null)" = crash ] && exit 0
n=5554
while [ -e "$S/emulators/emulator-$n" ]; do n=$((n + 2)); done
echo "$avd" >"$S/emulators/emulator-$n"
echo "emulator-$n" >"$S/active/$unit"
`,
  sleep: `echo "$1" >>"$S/sleep.log"
[ "$(cat "$S/mode" 2>/dev/null)" = stuck ] && exit 0
for f in "$S"/emulators/*; do [ -e "$f" ] && : >"$S/booted/\${f##*/}"; done
exit 0
`,
};

// The real one prints its notes on stdout too, ahead of the names.
const EMULATOR = `[ "$1" = -list-avds ] || exit 1
echo "INFO    | Storing crashdata in: /tmp/android-saiful/emu-crash-37.1.11.db, detection is enabled for process: 1"
cat "$S/avds"
`;

function scratch(t, { avds = ['ftc-lowend', 'ftc-modern', 'lareys'], emulator = true } = {}) {
  const dir = mkdtempSync(join(tmpdir(), 'dots-emulator-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  for (const d of ['bin', 'emulators', 'booted', 'active', 'sdk/emulator']) mkdirSync(join(dir, d), { recursive: true });
  writeFileSync(join(dir, 'avds'), avds.map((a) => a + '\n').join(''));
  const stub = (file, body) => {
    writeFileSync(file, '#!/bin/bash\nPATH=/usr/bin\n' + body);
    chmodSync(file, 0o755);
  };
  for (const [name, body] of Object.entries(STUBS)) stub(join(dir, 'bin', name), body);
  if (emulator) stub(join(dir, 'sdk/emulator/emulator'), EMULATOR);
  const run = (...args) =>
    spawnSync(bin, args, {
      encoding: 'utf8',
      // The script as stdin, the way `ssh host bash -s` runs one: an adb shell that read it would eat what follows.
      input: 'echo the rest of a script\n',
      env: { PATH: join(dir, 'bin') + ':/usr/bin', HOME: dir, ANDROID_HOME: join(dir, 'sdk'), S: dir },
    });
  const log = (name) => (existsSync(join(dir, name)) ? readFileSync(join(dir, name), 'utf8') : '');
  const up = (serial, avd, booted = true) => {
    writeFileSync(join(dir, 'emulators', serial), avd + '\n');
    if (booted) writeFileSync(join(dir, 'booted', serial), '');
  };
  return { dir, run, log, up };
}

test('boots the AVD as a unit of its own on ANGLE, and prints its serial once it has booted', (t) => {
  const s = scratch(t);
  const r = s.run('ftc-modern');
  assert.equal(r.status, 0, r.stderr);
  assert.equal(r.stdout, 'emulator-5554\n');
  assert.equal(
    s.log('systemd-run.log'),
    `--user --unit=dots-emulator-ftc-modern --collect --quiet ${s.dir}/sdk/emulator/emulator -avd ftc-modern -no-window -no-audio -no-boot-anim -no-snapshot -gpu swangle_indirect\n`,
  );
  assert.equal(s.log('sleep.log'), '5\n');
  assert.equal(s.log('stdin.log'), '');
});

test('reports an emulator of the AVD that is already up, whoever started it, and starts none', (t) => {
  const s = scratch(t);
  s.up('emulator-5556', 'ftc-modern');
  const r = s.run('ftc-modern');
  assert.equal(r.status, 0, r.stderr);
  assert.equal(r.stdout, 'emulator-5556\n');
  assert.equal(s.log('systemd-run.log'), '');
});

test("beside another AVD's emulator it boots its own and prints that one's serial", (t) => {
  const s = scratch(t);
  s.up('emulator-5554', 'lareys');
  const r = s.run('ftc-modern');
  assert.equal(r.status, 0, r.stderr);
  assert.equal(r.stdout, 'emulator-5556\n');
  assert.equal(s.log('adb.log'), '');
});

test('an emulator that died says where to read why, and exits 1', (t) => {
  const s = scratch(t);
  writeFileSync(join(s.dir, 'mode'), 'crash');
  const r = s.run('ftc-lowend');
  assert.equal(r.status, 1);
  assert.equal(r.stdout, '');
  assert.equal(
    r.stderr,
    'dots-emulator: the emulator of ftc-lowend stopped; journalctl --user -u dots-emulator-ftc-lowend.service and coredumpctl list say why\n',
  );
});

test('gives up after five minutes of an emulator that never finishes its boot', (t) => {
  const s = scratch(t);
  writeFileSync(join(s.dir, 'mode'), 'stuck');
  const r = s.run('lareys');
  assert.equal(r.status, 1);
  assert.equal(r.stderr, 'dots-emulator: lareys did not finish booting in five minutes\n');
  assert.equal(s.log('sleep.log'), '5\n'.repeat(60));
});

test('an AVD this machine does not have, or none, is a usage error that lists the ones it has', (t) => {
  const s = scratch(t);
  for (const args of [[], ['pixel'], ['stop'], ['ftc-modern', 'extra']]) {
    const r = s.run(...args);
    assert.equal(r.status, 2, args.join(' '));
    assert.equal(r.stderr, 'usage: dots-emulator [stop] <avd>; AVDs here: ftc-lowend ftc-modern lareys\n');
  }
  assert.equal(s.log('systemd-run.log'), '');
});

test('a machine with no emulator says so', (t) => {
  const s = scratch(t, { emulator: false });
  const r = s.run('lareys');
  assert.equal(r.status, 1);
  assert.equal(r.stderr, `dots-emulator: this machine has no Android emulator (${s.dir}/sdk/emulator/emulator)\n`);
});

test('stop ends the unit, and through its console an emulator of the AVD started outside it', (t) => {
  const s = scratch(t);
  assert.equal(s.run('ftc-modern').status, 0);
  s.up('emulator-5558', 'lareys');
  let r = s.run('stop', 'ftc-modern');
  assert.equal(r.status, 0, r.stderr);
  assert.ok(s.log('systemctl.log').includes('stop dots-emulator-ftc-modern.service\n'));
  assert.ok(!existsSync(join(s.dir, 'emulators/emulator-5554')));
  assert.equal(s.log('adb.log'), '');

  r = s.run('stop', 'lareys');
  assert.equal(r.status, 0, r.stderr);
  assert.equal(s.log('adb.log'), 'kill emulator-5558\n');
});
