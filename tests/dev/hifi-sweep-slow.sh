#!/usr/bin/env bash
# Slowed 20 times, Hi-Fi's sweep runs 4.4 s: half-way the pointer is mid-screen and red on screen, and the bar's lit lamp is still dark; at the end it is amber.
{
export DOTS_MOTION_SLOWDOWN=20
source "$(dirname "$0")/lib.sh"
unset TMUX

paper_layer() { niri msg -j layers | jq -e 'any(.[]; .namespace == "dots-paper" and .layer == "Background")' >/dev/null; }
until_ok 5000 paper_layer
until_ok 5000 shell_status >/dev/null

margins() { timeout 0.5 qs ipc call margins state 2>/dev/null; }
status_at_rest() { shell_status | jq -e --arg t "$1" '.theme == $t and .transition == ""' >/dev/null; }
pointer() { shell_status | jq -r '.pointer'; }
read -r ox oy w h < <(niri msg -j outputs | jq -r 'first(.[]).logical | "\(.x) \(.y) \(.width) \(.height)"')
y=$((oy + h / 4 / 16 * 16 + 3))
pixel() { grim -s 1 -t ppm -g "$((ox + $1)),$((oy + $2)) 1x1" - | mean_rgb; }

# The lit lamp's centre, read in Hi-Fi at rest.
legacy_theme hi-fi >/dev/null
until_ok 10000 status_at_rest hi-fi
lit_lamp() { margins | jq -e '.drawn.lamps | any(.lit)' >/dev/null; }
until_ok 2000 lit_lamp
read -r lx ly < <(margins | jq -r '.drawn.lamps[] | select(.lit) | .box | "\(.x + .w / 2 | floor) \(.y + .h / 2 | floor)"' | head -1)
echo "     lit lamp at $lx $ly"

legacy_theme blueprint >/dev/null
until_ok 10000 status_at_rest blueprint
sleep 0.5

start=$(now_ms)
legacy_theme hi-fi >/dev/null &
pid=$!
# Half the 4.4 s sweep, after the handover hifi-sweep.sh measured.
while (($(now_ms) - start < 50 + 2200)); do sleep 0.01; done
p0=$(pointer)
row=$(mktemp)
grim -s 1 -t ppm -g "$ox,$y ${w}x1" "$row"
p1=$(pointer)
lamp_half=$(pixel "$lx" "$ly")
wait "$pid"
echo "     pointer $p0 before the grab, $p1 after it"

mid_pointer() { node -e 'const p = Number(process.argv[1]); process.exit(p >= 0.4 && p <= 0.6 ? 0 : 1)' "$1"; }
check "half-way, status reports pointer $p0, between 0.4 and 0.6" mid_pointer "$p0"
# Red within 3 px of where the pointer was, between the reads either side of the grab.
red_at_pointer() {
  node -e '
    const buf = require("fs").readFileSync(process.argv[1]);
    const head = buf.toString("latin1").match(/^P6\s+(\d+)\s+(\d+)\s+(\d+)\s/);
    const w = +head[1], px = buf.subarray(head[0].length);
    const from = Math.floor(Number(process.argv[2]) * w) - 3, to = Math.ceil(Number(process.argv[3]) * w) + 3;
    const red = [];
    for (let x = 0; x < w; x++) if (px[x * 3] > 200 && px[x * 3 + 1] < 110) red.push(x);
    console.log("     red columns:", red.join(" ") || "none", "pointer span:", from, "to", to);
    process.exit(red.some((x) => x >= from && x <= to) ? 0 : 1);
  ' "$row" "$1" "$2"
}
check "half-way, the row has red #FB4934 within 3 px of the pointer" red_at_pointer "$p0" "$p1"
rm -f "$row"
dark() { local r g b; read -r r g b <<<"$1"; ((r < 100 && g < 100 && b < 100)); }
check "half-way, the lit lamp is still unlit-looking ($lamp_half)" dark "$lamp_half"

until_ok 6000 status_at_rest hi-fi
amber() { local r g b; read -r r g b < <(pixel "$lx" "$ly"); ((r - 250 <= 12 && 250 - r <= 12 && g - 189 <= 12 && 189 - g <= 12 && b - 47 <= 12 && 47 - b <= 12)); }
until_ok 1000 amber
check "at the end the lamp is lit amber #FABD2F ($(pixel "$lx" "$ly"))" amber

timers_one() { shell_status | jq -e '.timers == 1' >/dev/null; }
check "after the sweep status reports timers 1" timers_one

errors=$(journalctl --user -u "$DOTS_DEV_UNIT" --no-pager -o cat | grep -E 'Failed to load|ShaderEffect|QShader|\.qsb|Paper.qml|PaperFill.qml')
[ -n "$errors" ] && echo "$errors"
check "the shell's journal has no load or shader error" test -z "$errors"

exit $((fails > 0))
}
