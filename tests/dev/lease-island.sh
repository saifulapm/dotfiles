#!/usr/bin/env bash
# While an agent holds a lease the island draws who and the time left in place of the clock, in each theme's words, and its last minute in each theme's warning.
{
source "$(dirname "$0")/lib.sh"

island() { timeout 0.5 qs ipc call island state 2>/dev/null; }
state_is() { island | jq -e "$1" >/dev/null 2>&1; }
lock_is() { timeout 0.5 qs ipc call lock state 2>/dev/null | jq -e "$1" >/dev/null 2>&1; }
status_theme() { shell_status | jq -e --arg t "$1" '.theme == $t' >/dev/null; }
no_transition() { shell_status | jq -e '.transition == ""' >/dev/null; }
# A switch plays its transition over the old frame, so a capture waits for it to end and the next frame to land.
in_theme() { "$repo/bin/dots" theme "$1" >/dev/null; until_ok 2000 status_theme "$1"; until_ok 2000 no_transition; sleep 0.3; }
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

for theme in paper artboard blueprint; do
  in_theme "$theme"
  settled '.mode == "lease"'
  echo "     $theme: $(island | jq -c '{text, warning, lease}')"
  case $theme in
    paper) who=CLAUDE word=AGENT width=300 pad=14 ;;
    artboard) who=claude word=Agent width=264 pad=16 ;;
    blueprint) who=CLAUDE word=AGENT width=320 pad=16 ;;
  esac
  check "$theme: island state reads the lease with $who, out of its warning" state_is ".mode == \"lease\" and (.text | contains(\"$who\")) and .warning == false"
  check "$theme: the slot is the board's $width px, with the time at its right edge" state_is ".drawn == $width and .lease.timeRight == $width - $pad"
  read_back=$(ocr)
  check "$theme: the box draws the slot where the clock was (tesseract read '$read_back')" grep -qiF "$word" <<<"$read_back"
done
check "blueprint: the time counts down as T−m:ss in cyan" state_is '(.lease.time | test("^T−[01]:[0-5][0-9]$")) and .lease.timeColor == "#7fe3f0"'
in_theme paper
settled '.mode == "lease"'
check "paper: the time draws in Instrument Serif" state_is '.lease.timeFont == "Instrument Serif"'

# 45 s left is inside the last minute.
timeout 0.5 qs ipc call lock renew claude 0.75 >/dev/null
settled '.warning == true'
check "with 42 s left, island state reports warning, the time as 0:ss" state_is '.warning == true and (.lease.time | test("^0:4[0-5]$"))'
sheet=$(near 250 246 236)
check "paper: the island flips to the surface sheet ($sheet px of #FAF6EC)" test "$sheet" -gt 1500
check "paper: with a vermilion rule and time" state_is '.lease.timeColor == "#c8381e" and (.lease.fill | ascii_downcase) == "#faf6ec" and (.lease.frame | ascii_downcase) == "#c8381e"'
in_theme artboard
settled '.mode == "lease"'
chip=$(near 255 241 232)
check "artboard: the time sits in the board's chip, and the dot in its ring ($chip px of #FFF1E8)" test "$chip" -gt 300
check "artboard: in #B4380B" state_is '.lease.timeColor == "#b4380b" and .lease.chip == "#fff1e8"'
in_theme blueprint
settled '.mode == "lease"'
amber=$(near 255 181 71)
check "blueprint: the time turns amber ($amber px of #FFB547)" test "$amber" -gt 40
check "blueprint: the time and the frame turn amber" state_is '.lease.timeColor == "#ffb547" and (.lease.frame | ascii_downcase) == "#ffb547"'

timeout 0.5 qs ipc call lock renew claude 15 >/dev/null
settled '.warning == false'
check "renew claude 15 brings the normal look back" state_is '.warning == false and .lease.timeColor == "#7fe3f0"'

# Mod+I opens the lease card; niri runs no binds for wtype, so the check spawns the bind's command.
mod_i() { niri msg action spawn -- dots-call island focus; }
mod_i
settled '.mode == "leaseCard" and .focused'
echo "     card: $(island | jq -c .lease)"
check "Mod+I opens Blueprint's card: the title, WHO, SINCE, LEFT, the blocks and the keys" state_is '.lease.card and .lease.layout == "sheet" and .drawn == 420 and .lease.title == "CLAUDE HAS THE SESSION" and .lease.who == "CLAUDE" and (.lease.unlocked | test("^UNLOCKED [0-2][0-9]:[0-5][0-9]$")) and (.lease.time | startswith("T−1")) and .lease.bar == "blocks" and .lease.keys == "[↵] LOCK NOW · [ESC] CLOSE"'
wtype -k Escape
settled '.mode == "lease"'
for theme in paper artboard; do
  in_theme "$theme"
  settled '.mode == "lease"'
  mod_i
  settled '.mode == "leaseCard" and .focused'
  echo "     $theme card: $(island | jq -c '{drawn, lease}')"
  case $theme in
    paper) want='.lease.layout == "print" and .drawn == 420 and .lease.who == "claude" and (.lease.unlocked | startswith("unlocked ")) and (.lease.time | test("^1[45]:[0-5][0-9]$")) and .lease.keys == "↵ LOCK NOW · ESC CLOSE" and .lease.label == "" and (.lease.handles | not)' ;;
    artboard) want='.lease.layout == "card" and .drawn == 440 and .lease.who == "claude" and (.lease.unlocked | startswith("unlocked ")) and .lease.bar == "round" and .lease.keys == "↵ lock now · esc close" and .lease.label == "Island" and .lease.handles and .lease.timeColor == "#ffffff"' ;;
  esac
  check "$theme: Mod+I opens the board's card" state_is "$want"
  wtype -k Escape
  settled '.mode == "lease"'
done
in_theme blueprint
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
check "a name with a newline and U+202E draws as one line ($(island | jq -c .lease.who))" state_is '.lease.who == "CL AUDE X" and .lease.lines == 1'
niri msg action spawn -- dots-call lock lock
until_ok 3000 lock_is '.locked and .secure'
unlock "$(printf 'x%.0s' {1..200})" 5
settled '.mode == "lease"'
check "a 200-character name elides before the time, inside the slot's 320 px ($(island | jq -c '{drawn, t: .lease.timeRight}'))" state_is '.lease.elided and .lease.lines == 1 and .drawn == 320 and .lease.timeRight == 304'
mod_i
settled '.mode == "leaseCard" and .focused'
check "and on the card it elides on one line" state_is '.lease.elided and .drawn == 420'
wtype -k Escape
settled '.mode == "lease"'

niri msg action spawn -- dots-call lock lock
until_ok 3000 lock_is '.locked and .secure'
wtype dots-test-pass
wtype -k Return
until_ok 3000 lock_is '.locked == false'
in_theme paper

exit $((fails > 0))
}
