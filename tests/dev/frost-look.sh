#!/usr/bin/env bash
# Frost draws Artboard's layout in its own dark colours: Control's and the launcher's lit row is opaque #475666, the launcher names in Inter, and the lit name reads at 4.5:1 or more against the fill drawn behind it; Artboard keeps its #EEF1FF row.
{
source "$(dirname "$0")/lib.sh"

control_state() { timeout 0.5 qs ipc call control state 2>/dev/null; }
launcher_state() { timeout 0.5 qs ipc call launcher state 2>/dev/null; }
control_is() { control_state | jq -e "$1" >/dev/null; }
launcher_is() { launcher_state | jq -e "$1" >/dev/null; }
status_theme() { shell_status | jq -e --arg t "$1" '.theme == $t' >/dev/null; }
in_theme() { legacy_theme "$1" >/dev/null; until_ok 2000 status_theme "$1"; until_ok 2000 eval "shell_status | jq -e '.transition == \"\"' >/dev/null"; }
# niri runs no binds for wtype's virtual keyboard, so the check spawns each bind's command through niri.
open_control() { niri msg action spawn -- dots-call control toggle; until_ok 3000 control_is '.open and .keyboard and .cursorBox != null and .settled'; }
close_control() { wtype -k Escape; until_ok 2000 control_is '.open == false and .drawing == false'; }
open_launcher() { niri msg action spawn -- dots-call launcher toggle; until_ok 3000 launcher_is '.open and .query == "" and .keyboard and .settled'; }
close_launcher() { wtype -k Escape; until_ok 2000 launcher_is '.open == false'; }
# The state's box $1 as a grim geometry; with $2-$5, the part of it at x and y offsets $2 $3, $4 by $5 px.
geo() { jq -r --arg b "$1" --argjson dx "${2:-0}" --argjson dy "${3:-0}" --argjson w "${4:-0}" --argjson h "${5:-0}" '.[$b] | "\(.x + $dx | floor),\(.y + $dy | floor) \(if $w > 0 then $w else .w | floor end)x\(if $h > 0 then $h else .h | floor end)"'; }
# Pixels of geometry $1 within $5 of r g b.
near() {
  grim -s 1 -t ppm -g "$1" - | node -e '
    const b = require("fs").readFileSync(0), [r, g, bl, tol] = process.argv.slice(1).map(Number);
    const head = b.toString("latin1").match(/^P6\s+(\d+)\s+(\d+)\s+(\d+)\s/), px = b.subarray(head[0].length);
    let n = 0;
    for (let i = 0; i < head[1] * head[2]; i++) if (Math.abs(px[i * 3] - r) <= tol && Math.abs(px[i * 3 + 1] - g) <= tol && Math.abs(px[i * 3 + 2] - bl) <= tol) n++;
    console.log(n);
  ' "$2" "$3" "$4" "$5"
}
# The WCAG contrast of the text drawn in geometry $1 against the fill behind it: the fill is the box's commonest colour, the text its tenth most distant pixel, so a stray pixel cannot pass it.
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
    const f = lum(fillAt);
    const ratios = [];
    for (let i = 0; i < n; i++) { const l = lum(i); ratios.push((Math.max(l, f) + 0.05) / (Math.min(l, f) + 0.05)); }
    ratios.sort((a, z) => z - a);
    console.log((ratios[9] ?? 1).toFixed(2), "#" + fillKey.toString(16).padStart(6, "0"));
  '
}

until_ok 5000 shell_status >/dev/null

in_theme frost
open_control
check "frost: Control's cursor row's fill is #475666 ($(control_state | jq -c .cursorFill))" control_is '.cursorFill == "#475666"'
row=$(near "$(control_state | geo cursorBox 60 4 200 8)" 71 86 102 3)
check "frost: Control's cursor row draws #475666 across its width ($row of 1600 px)" test "$row" -gt 1200
close_control

open_launcher
wtype fo
until_ok 3000 launcher_is '.query == "fo" and .cursorName != null'
check "frost: the launcher names its rows in Inter ($(launcher_state | jq -c .nameFont))" launcher_is '.nameFont == "Inter"'
check "frost: the launcher's cursor row's fill is #475666 ($(launcher_state | jq -c .cursorFill))" launcher_is '.cursorFill == "#475666"'
read -r ratio fill < <(drawn_contrast "$(launcher_state | geo cursorNameBox)")
check "frost: the lit row's name reads at 4.5:1 or more against the fill drawn behind it ($ratio on $fill)" node -e 'process.exit(+process.argv[1] >= 4.5 ? 0 : 1)' "$ratio"
check "frost: that fill is the lit row's #475666 ($fill)" test "$fill" = "#475666"
check "frost: the pane is headed Launch · Apps with its matches counted ($(launcher_state | jq -c '[.label, .countText, .count]'))" launcher_is '.label == "Launch · Apps" and .countText == "\(.count) match\(if .count == 1 then "" else "es" end)"'
check "frost: the lit row is Foot with a ↵ badge ($(launcher_state | jq -c '[.results[.selected], .cursorBadge]'))" launcher_is '.results[.selected] == "Foot" and .cursorBadge == "↵"'
# The field is a well of nord0 at 70 % with a #434C5E edge, an accent › and caret; the keys are accent Maple Mono.
check "frost: the field's well is nord0 at 70 % with a #434c5e edge ($(launcher_state | jq -c '[.fieldFill, .fieldBorder]'))" launcher_is '.fieldFill == "#b32e3440" and .fieldBorder == "#434c5e"'
check "frost: the prompt is an accent › and the caret is accent ($(launcher_state | jq -c '[.prompt, .caretColor]'))" launcher_is '.prompt == {text: "›", color: "#88C0D0"} and .caretColor == "#88C0D0"'
check "frost: the key line's keys are #88c0d0 Maple Mono ($(launcher_state | jq -c '[.keyColor, .keyFont]'))" launcher_is '.keyColor == "#88c0d0" and .keyFont == "Maple Mono"'
# The well's top edge row reads #434C5E, and the first key's glyphs hold accent pixels the muted words never do.
edge=$(near "$(launcher_state | jq -r '.fieldBox | "\(.x + 40 | floor),\(.y | floor) 40x1"')" 67 76 94 6)
check "frost: the well's edge reads #434C5E on screen ($edge of 40 px)" test "$edge" -gt 30
wellpx=$(near "$(launcher_state | jq -r '.fieldBox | "\(.x + .w / 2 | floor),\(.y + 8 | floor) 20x8"')" 46 52 64 12)
check "frost: inside the well reads a nord0 tint ($wellpx of 160 px)" test "$wellpx" -gt 120
keypx=$(near "$(launcher_state | jq -r '.keyBox | "\(.x | floor),\(.y | floor) \(.w | ceil)x\(.h | ceil)"')" 136 192 208 24)
check "frost: the first key draws accent pixels on screen ($keypx px)" test "$keypx" -gt 6
close_launcher

in_theme artboard
open_launcher
check "artboard: the launcher has no well, no highlight and an ink key line ($(launcher_state | jq -c '[.fieldFill, .highlight, .keyColor]'))" launcher_is '.fieldFill == null and .highlight == null and .keyColor == "#15171b"'
inkpx=$(near "$(launcher_state | jq -r '.keyBox | "\(.x | floor),\(.y | floor) \(.w | ceil)x\(.h | ceil)"')" 21 23 27 30)
check "artboard: the first key draws ink pixels on screen ($inkpx px)" test "$inkpx" -gt 2
close_launcher
in_theme frost

# The YouTube App draws its magnifier in the theme's muted once the tokens arrive, not the black it starts in; Frost draws nothing near black, so any near-black pixel is that stale stroke.
yt_qml=$repo/shell/youtube.qml
yt_work=$(mktemp -d)
cleanup() { rm -rf "$yt_work"; }
yt_state() { timeout 0.5 qs ipc -p "$yt_qml" call youtube state 2>/dev/null; }
yt_up() { [ "$(niri msg -j windows | jq '[.[] | select(.app_id == "youtube")] | length')" = 1 ] && yt_state | jq -e '.firstFrameMs != null' >/dev/null; }
niri msg action spawn -- sh -c "exec env DOTS_DEV_DIR=$DOTS_DEV_DIR DOTS_YOUTUBE=$repo/bin/dev-fake-youtube XDG_DATA_HOME=$yt_work XDG_CACHE_HOME=$yt_work $repo/bin/dots-youtube"
until_ok 8000 yt_up
sleep 1
check "frost: YouTube's magnifier is Frost's muted ($(yt_state | jq -c .look.searchIcon))" eval 'yt_state | jq -e ".look.searchIcon == \"#aeb7c6\"" >/dev/null'
read -r ow oh < <(niri msg -j outputs | jq -r 'first(.[]).logical | "\(.width) \(.height)"')
black=$(near "0,0 $((ow / 2))x$((oh / 3))" 0 0 0 16)
check "frost: nothing in YouTube's top-left draws near black, so the magnifier took its colour ($black px)" test "$black" -eq 0
niri msg -j windows | jq -r '.[] | select(.app_id == "youtube") | .id' | xargs -r -I{} niri msg action close-window --id {}

in_theme artboard
open_control
check "artboard: Control's cursor row's fill is still #EEF1FF ($(control_state | jq -c .cursorFill))" control_is '.cursorFill == "#eef1ff"'
row=$(near "$(control_state | geo cursorBox 60 4 200 8)" 238 241 255 3)
check "artboard: Control's cursor row draws #EEF1FF across its width ($row of 1600 px)" test "$row" -gt 1200
close_control

in_theme paper
exit $((fails > 0))
}
