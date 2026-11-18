#!/usr/bin/env bash
# Goals as board 8 draws it in the island: text in the island's ink on its fill, goal tiles with deadline chips (danger on the day), 16 px round checkboxes that fill and strike through when done, Done · N folding at the bottom, no key hint, and the delete question in the danger tone.
{
source "$(dirname "$0")/lib.sh"

store="$DOTS_DEV_DIR/data/dots/goals/dev.json"
goals_state() { timeout 0.5 qs ipc call goals state 2>/dev/null; }
state_is() { goals_state | jq -e "$@" >/dev/null 2>&1; }
desk_up() { niri msg -j layers | jq -e 'any(.[]; .namespace == "dots-margins")' >/dev/null; }
open_goals() {
  until_ok 10000 desk_up
  niri msg action spawn -- dots-call goals toggle
  until_ok 3000 state_is '.open and .keyboard and .settled'
}
# Presses j or k until the row of kind $1 with text $2 is selected.
select_row() {
  local i n key
  for n in 1 2 3 4 5 6 7 8; do
    i=$(goals_state | jq --arg k "$1" --arg t "$2" '[.rows[] | .kind + ":" + .text] | index($k + ":" + $t)')
    [ -n "$i" ] && [ "$i" != null ] || return 1
    state_is --argjson i "$i" '.selected == $i' && return 0
    key=j
    state_is --argjson i "$i" '.selected > $i' && key=k
    wtype "$key"
    sleep 0.1
  done
  return 1
}
geo() { goals_state | jq -r "$1"' | "\(.x | floor),\(.y | floor) \(.w | ceil)x\(.h | ceil)"'; }
# A state colour such as .danger as "r g b".
rgb_of() { goals_state | jq -r "$1" | node -e 'const h = require("fs").readFileSync(0, "utf8").trim().slice(-6); console.log([0, 2, 4].map((i) => parseInt(h.slice(i, i + 2), 16)).join(" "))'; }
# How many pixels of geometry $1 lie within $5 of r g b.
near() {
  grim -s 1 -t ppm -g "$1" - | node -e '
    const b = require("fs").readFileSync(0), [r, g, bl, tol] = process.argv.slice(1).map(Number);
    const head = b.toString("latin1").match(/^P6\s+(\d+)\s+(\d+)\s+(\d+)\s/), px = b.subarray(head[0].length);
    let n = 0;
    for (let i = 0; i < head[1] * head[2]; i++) if (Math.abs(px[i * 3] - r) <= tol && Math.abs(px[i * 3 + 1] - g) <= tol && Math.abs(px[i * 3 + 2] - bl) <= tol) n++;
    console.log(n);
  ' "$2" "$3" "$4" "$5"
}
# The 10th highest contrast in geometry $1 against its commonest colour, and that colour: the text against the fill drawn behind it.
drawn_contrast() {
  grim -s 1 -t ppm -g "$1" - | node -e '
    const b = require("fs").readFileSync(0);
    const head = b.toString("latin1").match(/^P6\s+(\d+)\s+(\d+)\s+(\d+)\s/), px = b.subarray(head[0].length), n = head[1] * head[2];
    const lum = (i) => [0, 1, 2].map((c) => px[i * 3 + c] / 255).map((v) => (v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4)).reduce((s, v, c) => s + v * [0.2126, 0.7152, 0.0722][c], 0);
    const counts = new Map();
    for (let i = 0; i < n; i++) { const k = px.readUIntBE(i * 3, 3); counts.set(k, (counts.get(k) ?? 0) + 1); }
    const fillKey = [...counts].sort((a, z) => z[1] - a[1])[0][0];
    let fillAt = 0;
    while (px.readUIntBE(fillAt * 3, 3) !== fillKey) fillAt++;
    const f = lum(fillAt), ratios = [];
    for (let i = 0; i < n; i++) { const l = lum(i); ratios.push((Math.max(l, f) + 0.05) / (Math.min(l, f) + 0.05)); }
    ratios.sort((a, z) => z - a);
    console.log((ratios[9] ?? 1).toFixed(2), "#" + fillKey.toString(16).padStart(6, "0"));
  '
}

# Ship v2 due in 3 days, Tax due tonight, Read with ch 1 done and ch 2 not, and two done goals; goals.mjs builds the store.
mkdir -p "$(dirname "$store")"
node --input-type=module - "$repo/shell/lib/goals.mjs" >"$store.tmp" <<'JS'
const G = await import(process.argv[2]);
const now = Date.now(), tonight = new Date(new Date().setHours(23, 59, 0, 0)).getTime();
let s = G.emptyStore();
s = G.addGoal(s, 'Ship v2', now + 71 * 3600000, now, 'a');
s = G.addGoal(s, 'Tax', tonight, now, 'b');
s = G.addGoal(s, 'Read', null, now, 'c');
s = G.addTask(s, 'c', 'ch 1', now, 't1');
s = G.addTask(s, 'c', 'ch 2', now, 't2');
s = G.toggleTask(s, 'c', 't1', now);
s = G.addGoal(s, 'Old', null, now, 'd');
s = G.addGoal(s, 'Older', null, now, 'e');
s = G.toggleGoal(s, 'd', now);
s = G.toggleGoal(s, 'e', now);
console.log(JSON.stringify(s));
JS
mv "$store.tmp" "$store"

open_goals
until_ok 3000 state_is '.count == 3'
echo "     goals: $(goals_state | jq -c '{rows: [.rows[] | .text], blocks: [.blocks[] | {kind, text, chip: .chip.text}]}')"

# The heading sits on the bare fill, so the commonest colour around it is the fill and its text is the island's ink.
check "the heading draws in the island's ink ($(goals_state | jq -c '[.heading.text, .heading.color, .on]'))" state_is '.heading.text == "Goals" and .heading.color == .on'
read -r ratio drawn < <(drawn_contrast "$(geo .heading.box)")
fill=$(goals_state | jq -r '.fill | ascii_downcase')
check "on the island's fill ($drawn, fill $fill, contrast $ratio)" bash -c "[ '$drawn' = '$fill' ] && node -e 'process.exit(+process.argv[1] >= 4.5 ? 0 : 1)' '$ratio'"
read -r r g b < <(rgb_of .on)
ink=$(near "$(geo .heading.box)" "$r" "$g" "$b" 24)
check "and draws ink pixels ($ink px)" test "$ink" -gt 10
check "no key hint is in the state, and nothing is drawn under Done · 2 ($(goals_state | jq -c '{hint, last: .blocks[-1].text, cardBox, done: .blocks[-1].box}'))" state_is '(has("hint") | not) and (.cardBox.y + .cardBox.h - (.blocks[-1].box.y + .blocks[-1].box.h)) <= 20'

check "each goal is a tile, the selected one lighter ($(goals_state | jq -c '[.blocks[] | select(.kind == "goal") | .color]'))" state_is '. as $s | [.blocks[] | select(.kind == "goal") | .color] as $c | ($c | length) == 3 and ([$c[] | select(. == $s.sel)] | length) == 1 and all($c[]; . == $s.tile or . == $s.sel)'
check "Ship v2's chip reads 3d in the muted tone ($(goals_state | jq -c '.blocks[] | select(.text == "Ship v2") | .chip | {text, color}'))" state_is '(.blocks[] | select(.text == "Ship v2") | .chip) as $c | $c.text == "3d" and $c.color == .muted'
check "Tax, due today, has its chip in the danger tone ($(goals_state | jq -c '.blocks[] | select(.text == "Tax") | .chip | {text, color, glyph}'))" state_is '(.blocks[] | select(.text == "Tax") | .chip) as $c | ($c.text | test("^([0-9]+h|late)$")) and $c.color == .danger and $c.glyph == 983277'
check "Read, with no deadline, has no chip" state_is '(.blocks[] | select(.text == "Read") | .chip) == null'
read -r r g b < <(rgb_of .danger)
red=$(near "$(geo '.blocks[] | select(.text == "Tax") | .chip.box')" "$r" "$g" "$b" 40)
check "the Tax chip draws danger pixels ($red px)" test "$red" -gt 4

check "Done · 2 is the last thing drawn, behind a chevron ($(goals_state | jq -c '.blocks[-1] | {kind, text, glyph}'))" state_is '.blocks[-1] as $d | $d.kind == "done" and $d.text == "Done · 2" and $d.glyph == 983362 and all(.blocks[:-1][]; .box.y + .box.h <= $d.box.y)'
check "and the done goals stay folded under it" state_is '[.rows[] | .text] == ["Ship v2", "Tax", "Read", "Done · 2"]'

# Enter unfolds Read: ch 1 is done, ch 2 is not.
select_row goal Read
wtype -k Return
until_ok 2000 state_is '(.rows | length) == 6'
task() { goals_state | jq -c --arg t "$1" '.blocks[] | .tasks[]? | select(.text == $t)'; }
task_is() { task "$1" | jq -e --argjson s "$(goals_state)" "$2" >/dev/null 2>&1; }
check "an open task has a 16 px round checkbox, a 1.5 px muted ring with nothing in it ($(task 'ch 2'))" task_is 'ch 2' '.check.w == 16 and .check.h == 16 and .check.radius == 8 and .check.ringWidth == 1.5 and .check.ring == $s.muted and .check.glyph == null and .strike == false and .ink == $s.on'
check "a done task's box is filled with the ink, holds a check, and its text is muted and struck through ($(task 'ch 1'))" task_is 'ch 1' '.check.w == 16 and .check.color == $s.on and .check.glyph == 983340 and .strike and .ink == $s.muted'

select_row task "ch 2"
read -r r g b < <(rgb_of .on)
before=$(near "$(geo '.blocks[] | .tasks[]? | select(.text == "ch 2") | .check.box')" "$r" "$g" "$b" 30)
wtype -k space
until_ok 2000 task_is 'ch 2' '.strike'
check "Space on ch 2 fills its box and strikes its text through ($(task 'ch 2'))" task_is 'ch 2' '.check.color == $s.on and .check.glyph == 983340 and .strike and .ink == $s.muted'
sleep 0.2
after=$(near "$(geo '.blocks[] | .tasks[]? | select(.text == "ch 2") | .check.box')" "$r" "$g" "$b" 30)
check "and the box draws filled ($before ink px before, $after after)" test "$after" -gt $((before + 60))

wtype d
until_ok 2000 state_is '.confirm and .confirmLabel != null'
check "d asks whether to delete ch 2, by name, in the danger tone ($(goals_state | jq -c '.confirmLabel | {text, color}'))" state_is '.confirmLabel.text == "Delete “ch 2”?" and .confirmLabel.color == .danger'
read -r r g b < <(rgb_of .danger)
red=$(near "$(geo .confirmLabel.box)" "$r" "$g" "$b" 40)
check "the question draws danger pixels ($red px)" test "$red" -gt 4
wtype n
until_ok 2000 state_is '.confirm == false'

# A forged title in the file: a newline, U+202E and an ESC draw as one line, the store keeps the raw text.
forged=$(printf 'two\nlines ‮RLO \033[31mesc')
node --input-type=module - "$repo/shell/lib/goals.mjs" "$store" "$forged" >"$store.tmp" <<'JS'
const G = await import(process.argv[2]);
const { readFileSync } = await import("node:fs");
const s = G.parseStore(readFileSync(process.argv[3], "utf8"));
console.log(JSON.stringify(G.addGoal(s, process.argv[4], null, Date.now(), "f")));
JS
mv "$store.tmp" "$store"
until_ok 3000 state_is '.count == 4'
echo "     forged: $(goals_state | jq -c '.blocks[] | select(.kind == "goal" and (.text | startswith("two"))) | {text, lines, box}')"
check "a forged title draws as one line with no newline, control or bidi character" state_is '.blocks[] | select(.kind == "goal" and (.text | startswith("two"))) | .lines == 1 and (.text | test("[\u0000-\u001f‮]") | not)'
check "and its tile is as high as Tax's, a one-line goal ($(goals_state | jq -c '[.blocks[] | select(.kind == "goal" and (.text == "Tax" or (.text | startswith("two")))) | .box.h]'))" state_is '[.blocks[] | select(.kind == "goal" and (.text == "Tax" or (.text | startswith("two")))) | .box.h] | length == 2 and .[0] == .[1]'

wtype -k Escape
until_ok 2000 state_is '.open == false and .drawing == false'

exit $((fails > 0))
}
