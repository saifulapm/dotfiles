#!/usr/bin/env bash
# Slowed 4 times, a switch from catppuccin-mocha to rose-pine-dawn shows its middle: at 130 ms of its own time the paper and an open launcher are part way between the two schemes, not at either end. At full speed grim stalls for up to 130 ms while the switch renders, so no grab lands on that point.
{
export DOTS_DEV_SCHEME=catppuccin-mocha DOTS_MOTION_SLOWDOWN=4
slow=4
source "$(dirname "$0")/lib.sh"
unset TMUX

rest_in() { shell_status | jq -e --arg t "$1" '.theme == $t and .transition == ""' >/dev/null; }
until_ok 5000 rest_in catppuccin-mocha

# The launcher open over the paper, both read from one 1 px line per grab, timed against the shell's start stamp.
launcher_state() { timeout 0.5 qs ipc call launcher state 2>/dev/null; }
niri msg action spawn -- dots-call launcher toggle
until_ok 3000 eval "launcher_state | jq -e '.open and .settled and .cardBox != null' >/dev/null"
read -r cx cy < <(launcher_state | jq -r '.cardBox | "\(.x | floor) \(.y | floor)"')
# The paper 3 px into a 16 px cell left of the card, clear of its dots and above the day's passage; the card 4 px inside its top-left corner.
px=$(((cx - 40) / 16 * 16 + 3)) y=$((cy + 4))
span=$((cx + 4 - px + 1))
# Grabs go raw to files and are read after the switch, so each costs a grim and nothing more.
shots=$(mktemp -d)
cleanup() { rm -rf "$shots"; }
read_shot() {
  node -e '
    const b = require("fs").readFileSync(process.argv[1]);
    const px = b.subarray(b.toString("latin1").match(/^P6\s+\d+\s+\d+\s+\d+\s/)[0].length);
    const at = (x) => [0, 1, 2].map((c) => px[x * 3 + c]).join(" ");
    console.log(at(0), at(Number(process.argv[2])));
  ' "$1" "$((span - 1))"
}
stamps=()
start=$(now_ms)
"$repo/bin/dots" colorscheme rose-pine-dawn >/dev/null &
pid=$!
n=0
while (($(now_ms) - start < 3000)); do
  t0=$(now_ms)
  grim -s 1 -t ppm -g "$px,$y ${span}x1" "$shots/$n.ppm"
  stamps+=("$(((t0 + $(now_ms)) / 2))")
  n=$((n + 1))
done
wait "$pid"
grabs=()
for i in "${!stamps[@]}"; do grabs+=("${stamps[i]} $(read_shot "$shots/$i.ppm")"); done
until_ok 3000 rest_in rose-pine-dawn
began=$(shell_status | jq '.transitionStartedAt')
best="" gap=100000
for g in "${grabs[@]}"; do
  read -r t _ <<<"$g"
  d=$((t - began - 130 * slow))
  ((d < 0)) && d=$((-d))
  ((d < gap)) && gap=$d best=$g
done
[ -n "${FADE_DEBUG:-}" ] && for g in "${grabs[@]}"; do read -r t a b c d e f <<<"$g"; echo "  $((t - began)) paper $a $b $c card $d $e $f"; done
read -r t pr pg pb sr sg sb <<<"$best"
# Each channel's way from the old colour to the new, 0 to 1; part way is every channel inside 0.1 to 0.9.
partway() {
  node -e '
    const [from, to, at] = process.argv.slice(1).map((h) => h.length === 7 ? [1, 3, 5].map((i) => parseInt(h.slice(i, i + 2), 16)) : h.split(" ").map(Number));
    const f = at.map((v, i) => (v - from[i]) / (to[i] - from[i]));
    console.log(f.map((x) => x.toFixed(2)).join(" "));
    process.exit(f.every((x) => x >= 0.1 && x <= 0.9) ? 0 : 1);
  ' "$1" "$2" "$3"
}
check "a grab lands within 40 ms of 130 ms (x$slow) into the switch (${gap} ms off, ${#grabs[@]} grabs)" test "$gap" -le 40
check "130 ms in, the paper is part way from #11111B to #F2E9E1 ($pr $pg $pb: $(partway '#11111B' '#F2E9E1' "$pr $pg $pb"))" eval "partway '#11111B' '#F2E9E1' '$pr $pg $pb' >/dev/null"
check "130 ms in, the open launcher's fill is part way from #1E1E2E to #FAF4ED ($sr $sg $sb: $(partway '#1E1E2E' '#FAF4ED' "$sr $sg $sb"))" eval "partway '#1E1E2E' '#FAF4ED' '$sr $sg $sb' >/dev/null"

exit $((fails > 0))
}
