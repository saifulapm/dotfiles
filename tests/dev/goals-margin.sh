#!/usr/bin/env bash
# The top-right margin starts with the nearest-deadline active goal, from the goals store on disk.
source "$(dirname "$0")/lib.sh"

until_ok 5000 shell_status >/dev/null
margins() { timeout 0.5 qs ipc call margins state 2>/dev/null; }
store="$DOTS_DEV_DIR/data/dots/goals/dev.json"

# Builds a store with goals.mjs itself: each argument is title:hours-from-now (or title:none), a trailing :done marks it done.
make_store() {
  node --input-type=module - "$repo/shell/lib/goals.mjs" "$@" <<'JS'
const [, , lib, ...specs] = process.argv;
const G = await import(lib);
const now = Date.now();
let s = G.emptyStore();
specs.forEach((spec, i) => {
  const [title, hours, done] = spec.split(':');
  s = G.addGoal(s, title, hours === 'none' ? null : now + Number(hours) * 3600000, now, 'g' + i);
  if (done) s = G.toggleGoal(s, 'g' + i, now);
});
console.log(JSON.stringify(s));
JS
}
# Writes in place, which keeps the file's inode.
write_in_place() { make_store "$@" >"$store"; }
# A sync writes a temp file in the folder and renames it over the store.
write_by_rename() { make_store "$@" >"$store.tmp" && mv "$store.tmp" "$store"; }

right_starts() { margins | jq -e --arg p "$1" '.right.text | startswith($p)' >/dev/null 2>&1; }
shows() {
  until_ok 3000 right_starts "$1"
  echo "     margins: $(margins | jq -c .right)"
  right_starts "$1"
}

# The shell's clock is up to a minute behind, so deadlines sit mid-bucket (71 h reads 3d, 4.5 h reads 5h).
mkdir -p "$(dirname "$store")"
write_in_place "Ship v2:71" "Docs:288"
check "Ship v2 due in 3 days leads the margin" shows "Ship v2 · 3d  "

write_by_rename "Ship v2:4.5"
check "a store renamed over the old one: Ship v2 due in 5 hours" shows "Ship v2 · 5h  "

write_by_rename "Read:none"
check "a goal without a deadline leads by its title" shows "Read  "

write_by_rename "Read:none" "Ship v2:71"
check "a renamed store with a deadline goal puts it before the others" shows "Ship v2 · 3d  "

write_in_place "Ship v2:71:done"
no_goal() { margins | jq -e '.right.goal == "" and .right.text == ([.right.wifi, .right.battery, .right.date] | map(select(. != "")) | join("  "))' >/dev/null 2>&1; }
until_ok 3000 no_goal
echo "     margins: $(margins | jq -c .right)"
check "with no active goals the margin starts with the Wi-Fi text" no_goal

status=$(shell_status)
echo "     status: $status"
one_timer() { jq -e '.timers == 1' <<<"$status" >/dev/null; }
check "status reports one running timer" one_timer

exit $((fails > 0))
