#!/usr/bin/env bash
# While an agent holds a lease the island draws who and the time left in place of the clock, and its last minute in the warning colour.
{
source "$(dirname "$0")/lib.sh"

island() { timeout 0.5 qs ipc call island state 2>/dev/null; }
state_is() { island | jq -e "$1" >/dev/null 2>&1; }
lock_is() { timeout 0.5 qs ipc call lock state 2>/dev/null | jq -e "$1" >/dev/null 2>&1; }
settled() { until_ok 3000 state_is "$1 and .animating == false"; sleep 0.1; }
# An agent unlock turns the monitors off a second later, and the shell, a Qt client, draws no new frame without niri's frame callbacks, so the check wakes them as Saiful would.
unlock() {
  local n
  n=$(timeout 0.5 qs ipc call lock state | jq .monitorsOff)
  timeout 0.5 qs ipc call lock unlock "$@" >/dev/null
  until_ok 3000 lock_is ".locked == false and .monitorsOff > $n"
  niri msg action power-on-monitors
}
# The island's box: centred on the output, 10 px from the top.
box() { niri msg -j outputs | jq -r --argjson w "$(island | jq .drawn)" --argjson h "$(island | jq .height)" 'first(.[]).logical | "\(((.width - $w) / 2 + .x) | floor),\(.y + 10) \($w | floor)x\($h | floor)"'; }
# What tesseract reads in the box, light text made dark on light, at the output's own pixels.
ocr() {
  grim -t ppm -g "$(box)" - | node -e '
    const b = require("fs").readFileSync(0);
    const head = b.toString("latin1").match(/^P6\s+(\d+)\s+(\d+)\s+(\d+)\s/);
    const px = b.subarray(head[0].length), n = head[1] * head[2];
    let sum = 0;
    for (let i = 0; i < n * 3; i++) sum += px[i];
    const dark = sum / (n * 3) < 128, out = Buffer.alloc(n);
    for (let i = 0; i < n; i++) { const v = (px[i * 3] + px[i * 3 + 1] + px[i * 3 + 2]) / 3; out[i] = dark ? 255 - v : v; }
    process.stdout.write(Buffer.concat([Buffer.from(`P5 ${head[1]} ${head[2]} 255\n`), out]));
  ' | tesseract stdin stdout --psm 7 2>/dev/null | tr -d '\n'
}
# Pixels of the box within 12 of r g b.
near() {
  grim -s 1 -t ppm -g "$(box)" - | node -e '
    const b = require("fs").readFileSync(0), [r, g, bl] = process.argv.slice(1).map(Number);
    const head = b.toString("latin1").match(/^P6\s+(\d+)\s+(\d+)\s+(\d+)\s/), px = b.subarray(head[0].length);
    let n = 0;
    for (let i = 0; i < head[1] * head[2]; i++) if (Math.abs(px[i * 3] - r) <= 12 && Math.abs(px[i * 3 + 1] - g) <= 12 && Math.abs(px[i * 3 + 2] - bl) <= 12) n++;
    console.log(n);
  ' "$@"
}

until_ok 5000 shell_status >/dev/null
check "at rest the island is the clock" state_is '.mode == "rest" and .lease == null'
niri msg action spawn -- dots-call lock lock
until_ok 3000 lock_is '.locked and .secure'
unlock claude 2

settled '.mode == "lease"'
echo "     lease: $(island | jq -c '{text, warning, lease}')"
check "island state reads the lease with claude, out of its warning" state_is '.mode == "lease" and (.text | contains("claude")) and .warning == false'
check "the slot is 264 px, with the time at its right edge" state_is '.drawn == 264 and .lease.timeRight == 248'
read_back=$(ocr)
check "the box draws the slot where the clock was (tesseract read '$read_back')" grep -qiF Agent <<<"$read_back"

# 45 s left is inside the last minute.
timeout 0.5 qs ipc call lock renew claude 0.75 >/dev/null
settled '.warning == true'
check "with 42 s left, island state reports warning, the time as 0:ss" state_is '.warning == true and (.lease.time | test("^0:4[0-5]$"))'
chip=$(near 255 241 232)
check "the time sits in a chip, and the dot in its ring ($chip px of #FFF1E8)" test "$chip" -gt 300
check "the time turns #B4380B" state_is '.lease.timeColor == "#b4380b" and .lease.chip == "#fff1e8"'

timeout 0.5 qs ipc call lock renew claude 15 >/dev/null
settled '.warning == false'
check "renew claude 15 brings the normal look back" state_is '.warning == false and .lease.timeColor == "#ffffff" and .lease.chip == null'

# Mod+I opens the lease card; niri runs no binds for wtype, so the check spawns the bind's command.
mod_i() { niri msg action spawn -- dots-call island focus; }
mod_i
settled '.mode == "leaseCard" and .focused'
echo "     card: $(island | jq -c '{drawn, lease}')"
check "Mod+I opens the card: the name, the unlock time, the time left, the bar and the keys" state_is '.lease.card and .drawn == 440 and .lease.who == "claude" and (.lease.unlocked | test("^unlocked [0-2][0-9]:[0-5][0-9]$")) and (.lease.time | test("^1[45]:[0-5][0-9]$")) and .lease.bar == "round" and .lease.keys == "↵ lock now · esc close" and .lease.label == "Island" and .lease.timeColor == "#ffffff"'
wtype -k Escape
settled '.mode == "lease"'
check "Esc closes the card back to the slot, still unlocked" bash -c "$(declare -f state_is island lock_is); state_is '.mode == \"lease\" and .focused == false' && lock_is '.locked == false'"
mod_i
settled '.mode == "leaseCard" and .focused'
t0=$(now_ms)
wtype -k Return
until_ok 1000 lock_is '.locked'
took=$(($(now_ms) - t0))
check "Enter on the card locks within 1 s ($took ms)" lock_is '.locked and .heldBy == ""'

# A holder's name is anyone's text: one line, no bidi controls, elided inside the island.
niri msg action spawn -- dots-call lock lock
until_ok 3000 lock_is '.locked and .secure'
check "a lock ends the slot" state_is '.mode != "lease" and .lease == null'
timeout 0.5 qs ipc call lock unlock "$(printf 'cl\naude‮ x')" 5 >/dev/null
settled '.mode == "lease"'
check "a name with a newline and U+202E draws as one line ($(island | jq -c .lease.who))" state_is '.lease.who == "Agent · cl aude x" and .lease.lines == 1'
niri msg action spawn -- dots-call lock lock
until_ok 3000 lock_is '.locked and .secure'
unlock "$(printf 'x%.0s' {1..200})" 5
settled '.mode == "lease"'
check "a 200-character name elides before the time, inside the slot's 264 px ($(island | jq -c '{drawn, t: .lease.timeRight}'))" state_is '.lease.elided and .lease.lines == 1 and .drawn == 264 and .lease.timeRight == 248'
mod_i
settled '.mode == "leaseCard" and .focused'
check "and on the card it elides on one line" state_is '.lease.elided and .drawn == 440'
wtype -k Escape
settled '.mode == "lease"'

niri msg action spawn -- dots-call lock lock
until_ok 3000 lock_is '.locked and .secure'
wtype dots-test-pass
wtype -k Return
until_ok 3000 lock_is '.locked == false'

exit $((fails > 0))
}
