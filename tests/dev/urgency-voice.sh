#!/usr/bin/env bash
# The urgency marks read • 05  • 07, accent dots before ink numbers; with every mark drawn a long title still elides short of the island.
{
source "$(dirname "$0")/lib.sh"

margins() { timeout 0.5 qs ipc call margins state 2>/dev/null; }
marks_are() { margins | jq -e --arg want "$1" '.drawn.marks == $want' >/dev/null 2>&1; }
colors_are() { margins | jq -e --argjson want "$1" '.drawn.markColors | unique == ($want | sort)' >/dev/null 2>&1; }
focused_is() { niri msg -j focused-window | jq -e --arg t "$1" '.title == $t' >/dev/null 2>&1; }
bells="$DOTS_DEV_DIR/bells"
mkdir -p "$bells"
ringer() { niri msg action spawn -- foot -c /dev/null -o bell.urgent=yes -T "$1" sh -c "until [ -e '$bells/$1' ]; do sleep 0.05; done; printf '\a'; sleep 600"; until_ok 5000 focused_is "$1"; }
plain() { niri msg action spawn -- foot -c /dev/null -T "$1" sleep 600; until_ok 5000 focused_is "$1"; }
read -r ox oy < <(niri msg -j outputs | jq -r 'first(.[]).logical | "\(.x) \(.y)"')
# Accent #3D5AFE pixels, within 40 per channel, in the 140 px of the top-left margin before its end, where the marks sit.
accent_px() {
  local end
  end=$(margins | jq '.drawn.leftEnd | floor')
  grim -s 1 -t ppm -g "$((ox + end - 140)),$((oy + 14)) 140x22" - | node -e '
    const b = require("fs").readFileSync(0);
    const head = b.toString("latin1").match(/^P6\s+(\d+)\s+(\d+)\s+(\d+)\s/), px = b.subarray(head[0].length);
    let n = 0;
    for (let i = 0; i < head[1] * head[2]; i++) if (Math.abs(px[i * 3] - 50) <= 40 && Math.abs(px[i * 3 + 1] - 73) <= 40 && Math.abs(px[i * 3 + 2] - 206) <= 40) n++;
    console.log(n);
  '
}

until_ok 5000 shell_status >/dev/null
# Workspace 1 shows a 200-character title, and 4 and 6 hold quiet feet so every number up to 7 stays.
long=$(printf 'T%.0s' $(seq 200))
plain "$long"
for n in 2 3 4 5 6 7; do
  niri msg action focus-workspace "$n"
  case $n in 4 | 6) plain "quiet$n" ;; *) ringer "ws$n" ;; esac
done
niri msg action focus-workspace 1
until_ok 2000 focused_is "$long"

touch "$bells/ws5" "$bells/ws7"
until_ok 3000 marks_are "• 05  • 07"
echo "     drawn: $(margins | jq -c .drawn)"
check "the marks read • 05  • 07" marks_are "• 05  • 07"
check "accent dots, moved to read on the desk, before ink numbers" colors_are '["#3249ce","#15171b"]'
check "the two dots draw in the accent ($(accent_px) px)" test "$(accent_px)" -ge 4

touch "$bells/ws2" "$bells/ws3"
# A Text paints past its width unless it elides, so the check reads both its box and its elision.
short_of_island() { margins | jq -e '.drawn.leftElided and .drawn.leftEnd <= .drawn.lineEnd and .drawn.leftEnd > .drawn.lineEnd - 40' >/dev/null 2>&1; }
until_ok 3000 marks_are "• 02  • 03  • 05  +1"
until_ok 2000 short_of_island
echo "     $(margins | jq -c '.drawn | {marks, leftEnd, lineEnd}')"
check "• 02  • 03  • 05  +1 after a 200-character title that elides 8 px short of the island" eval 'marks_are "• 02  • 03  • 05  +1" && short_of_island'

exit $((fails > 0))
}
