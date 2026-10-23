#!/usr/bin/env bash
# dots theme recolours an open zathura, imv and mpv in each theme, and Chromium wears the theme's exact colours from its next start.
{
source "$(dirname "$0")/lib.sh"

work=$DOTS_DEV_DIR/app-themes
mkdir -p "$work"
out=$XDG_STATE_HOME/dots/theme-out
rgb() { printf '%d %d %d' "0x${1:1:2}" "0x${1:3:2}" "0x${1:5:2}"; }
token() { jq -r ".color.$1" "$out/shell.json"; }
near() { (($1 - $2 <= 6 && $2 - $1 <= 6)); }
pixel() { grim -s 1 -t ppm -g "$1,$2 1x1" - | mean_rgb; }
pixel_is() { local r g b; read -r r g b < <(pixel "$1" "$2"); read -r -a want <<<"$(rgb "$3")"; near "$r" "${want[0]}" && near "$g" "${want[1]}" && near "$b" "${want[2]}"; }
exact_is() { test "$(pixel "$1" "$2")" = "$(rgb "$3")"; }
# The window's top-left corner and size on the output, from niri's layout.
geometry() { niri msg -j windows | jq -r --arg a "$1" 'first(.[] | select(.app_id == $a) | .layout) | "\(.tile_pos_in_workspace_view[0] + .window_offset_in_tile[0] | floor) \(.tile_pos_in_workspace_view[1] + .window_offset_in_tile[1] | floor) \(.window_size[0]) \(.window_size[1])"'; }
has_window() { niri msg -j windows | jq -e --arg a "$1" 'any(.[]; .app_id == $a)' >/dev/null; }
close_all() { local id; for id in $(niri msg -j windows | jq -r --arg a "$1" '.[] | select(.app_id == $a) | .id'); do niri msg action close-window --id "$id"; done; }

# One page with a blue box and an outline, so zathura has an index to show; mupdf rebuilds the missing xref.
cat >"$work/page.pdf" <<'PDF'
%PDF-1.4
1 0 obj << /Type /Catalog /Pages 2 0 R /Outlines 5 0 R >> endobj
2 0 obj << /Type /Pages /Kids [3 0 R] /Count 1 >> endobj
3 0 obj << /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R >> endobj
4 0 obj << /Length 28 >> stream
0 0 1 rg 72 300 200 150 re f
endstream endobj
5 0 obj << /Type /Outlines /First 6 0 R /Last 6 0 R /Count 1 >> endobj
6 0 obj << /Title (One) /Parent 5 0 R /Dest [3 0 R /Fit] >> endobj
trailer << /Root 1 0 R >>
%%EOF
PDF
ffmpeg -loglevel error -y -f lavfi -i color=c=red:s=200x200 -frames:v 1 "$work/red.png"

"$repo/bin/dots" theme paper
themes=(blueprint artboard paper)

# mpv: two players on this display, each with the socket dots-ipc.lua opens.
mpv_socks() { local pid; for pid in $(pgrep -x mpv); do grep -qzxF "WAYLAND_DISPLAY=$WAYLAND_DISPLAY" "/proc/$pid/environ" 2>/dev/null && echo "$XDG_RUNTIME_DIR/mpv-$pid.sock"; done; }
# A socket a crash left behind, whose mpv is gone, must not stop a switch; socat killed outright leaves its socket as a crashed mpv does.
socat UNIX-LISTEN:"$XDG_RUNTIME_DIR/mpv-999999.sock",fork /dev/null &
stale=$!
until_ok 2000 test -S "$XDG_RUNTIME_DIR/mpv-999999.sock"
kill -9 "$stale"
wait "$stale" 2>/dev/null
for _ in 1 2; do
  niri msg action spawn -- mpv --no-config --idle --force-window --script="$repo/home/dot_config/mpv/scripts/dots-ipc.lua" --include="$out/mpv.conf"
done
two_mpv() { test "$(mpv_socks | while read -r s; do test -S "$s" && echo "$s"; done | wc -l)" = 2; }
until_ok 8000 two_mpv
ask_mpv() { echo "{\"command\":[\"get_property\",\"$2\"]}" | socat -t 0.5 - "UNIX-CONNECT:$1" | jq -r .data; }
mpv_all() { local s; for s in $(mpv_socks); do test "$(ask_mpv "$s" osd-color | tr A-F a-f)" = "#ff$(token ink | tr A-F a-f | cut -c2-)" || return 1; done; }
osc_all() { local s; for s in $(mpv_socks); do echo '{"command":["get_property","script-opts"]}' | socat -t 0.5 - "UNIX-CONNECT:$s" | jq -e --arg c "$(token surface | tr A-F a-f)" '.data["osc-background_color"] == $c' >/dev/null || return 1; done; }
check "both players draw the OSD in Paper's ink" mpv_all
for theme in "${themes[@]}"; do
  start=$(now_ms)
  "$repo/bin/dots" theme "$theme"
  check "dots theme $theme names no app that missed it ($(cat "$out/notice"))" test ! -s "$out/notice"
  until_ok 1000 mpv_all
  check "both players draw the OSD in $theme's ink $(($(now_ms) - start)) ms after the call" mpv_all
  check "both players' OSC sits on $theme's surface" osc_all
done
check "the stale mpv socket is gone" test ! -e "$XDG_RUNTIME_DIR/mpv-999999.sock"
socks=$(mpv_socks)
for s in $socks; do echo '{"command":["quit"]}' | socat -t 0.5 - "UNIX-CONNECT:$s" >/dev/null; done
none_left() { local s; for s in $socks; do test ! -e "$s" || return 1; done; }
until_ok 3000 none_left
check "each player's socket is gone after it quits" none_left
"$repo/bin/dots" theme paper
status=$?
check "dots theme with no mpv open exits 0" test "$status" = 0

# zathura reads this config, as ~/.config/zathura/zathurarc does, with the nested session's fragment.
mkdir -p "$work/zathura"
sed "s|^include .*|include $out/zathura|" <(chezmoi execute-template <"$repo/home/dot_config/zathura/zathurarc.tmpl") >"$work/zathura/zathurarc"
niri msg action spawn -- zathura --config-dir="$work/zathura" "$work/page.pdf"
until_ok 5000 has_window org.pwmt.zathura
sleep 1
read -r zx zy zw zh < <(geometry org.pwmt.zathura)
# Right of the page's middle is blank page; the window's left edge is zathura's background around the page.
page_x=$((zx + zw / 2 + zh / 5)) page_y=$((zy + zh / 2)) side_x=$((zx + 12))
check "zathura's page is white in Paper, recolouring off ($(pixel $page_x $page_y))" pixel_is $page_x $page_y '#FFFFFF'
check "zathura's background is Paper's paper ($(pixel $side_x $page_y))" pixel_is $side_x $page_y "$(token paper)"
for theme in "${themes[@]}"; do
  start=$(now_ms)
  "$repo/bin/dots" theme "$theme"
  paper=$(token paper)
  page=$paper
  [[ $(jq -r .mode "$out/shell.json") == light ]] && page='#FFFFFF'
  until_ok 1000 pixel_is $side_x $page_y "$paper"
  check "zathura's background is $theme's paper $(($(now_ms) - start)) ms after the call" pixel_is $side_x $page_y "$paper"
  check "zathura's page is $page in $theme ($(pixel $page_x $page_y))" pixel_is $page_x $page_y "$page"
done
# A switch while zathura shows its index, and then its search bar, still recolours the page.
wtype -k Tab
sleep 0.3
"$repo/bin/dots" theme blueprint
until_ok 1000 pixel_is $side_x $page_y "$(token paper)"
check "with the index open, zathura's background is Blueprint's paper ($(pixel $side_x $page_y))" pixel_is $side_x $page_y "$(token paper)"
wtype -k Tab
sleep 0.3
wtype /
sleep 0.2
"$repo/bin/dots" theme paper
until_ok 1000 pixel_is $page_x $page_y '#FFFFFF'
check "with the search bar open, zathura's page is white again in Paper ($(pixel $page_x $page_y))" pixel_is $page_x $page_y '#FFFFFF'
wtype -k Escape
close_all org.pwmt.zathura
until_ok 3000 bash -c '! niri msg -j windows | jq -e "any(.[]; .app_id == \"org.pwmt.zathura\")" >/dev/null'

# imv reads the rendered config, as ~/.config/imv/config links to it.
export imv_config=$out/imv.conf
niri msg action spawn -- env imv_config="$imv_config" imv "$work/red.png"
until_ok 5000 has_window imv
sleep 1
read -r ix iy iw ih < <(geometry imv)
check "imv's background is Paper's paper ($(pixel $((ix + 8)) $((iy + ih / 2))))" pixel_is $((ix + 8)) $((iy + ih / 2)) "$(token paper)"
for theme in "${themes[@]}"; do
  start=$(now_ms)
  "$repo/bin/dots" theme "$theme"
  until_ok 1000 pixel_is $((ix + 8)) $((iy + ih / 2)) "$(token paper)"
  check "imv's background is $theme's paper $(($(now_ms) - start)) ms after the call" pixel_is $((ix + 8)) $((iy + ih / 2)) "$(token paper)"
done
# An imv started after a switch draws its overlay text in the theme's ink.
"$repo/bin/dots" theme blueprint
close_all imv
until_ok 3000 bash -c '! niri msg -j windows | jq -e "any(.[]; .app_id == \"imv\")" >/dev/null'
niri msg action spawn -- env imv_config="$imv_config" imv -d "$work/red.png"
until_ok 5000 has_window imv
sleep 1
read -r ix iy iw ih < <(geometry imv)
ink_pixels() { grim -s 1 -t ppm -g "$ix,$iy ${iw}x40" - | node -e '
  const b = require("fs").readFileSync(0);
  const head = b.toString("latin1").match(/^P6\s+(\d+)\s+(\d+)\s+(\d+)\s/);
  const px = b.subarray(head[0].length), want = process.argv[1].match(/\w\w/g).map((h) => parseInt(h, 16));
  let n = 0;
  for (let i = 0; i < px.length; i += 3) if (Math.abs(px[i] - want[0]) <= 6 && Math.abs(px[i + 1] - want[1]) <= 6 && Math.abs(px[i + 2] - want[2]) <= 6) n++;
  console.log(n);
' "$(token ink | cut -c2-)"; }
check "imv opened in Blueprint draws its overlay text in Blueprint's ink ($(ink_pixels) pixels)" test "$(ink_pixels)" -ge 20
grim -s 1 "$work/imv-overlay.png"
close_all imv
until_ok 3000 bash -c '! niri msg -j windows | jq -e "any(.[]; .app_id == \"imv\")" >/dev/null'

# Chromium reads the managed policy from /etc, so it runs with an empty policy dir bound there, as on a machine the apply has cleaned; its profile is the check's own.
chromium() {
  niri msg action spawn -- bwrap --dev-bind / / --bind "$work/policy" /etc/chromium/policies/managed \
    chromium-browser --user-data-dir="$work/profile" --no-first-run --ozone-platform=wayland "--load-extension=$1" \
    'data:text/html,<body style="background:magenta">'
}
mkdir -p "$work/policy"
chromium_up() { niri msg -j windows | jq -e 'any(.[]; .app_id == "chromium-browser" and (.title | test("data:")))' >/dev/null; }
chromium_gone() { ! pgrep -x chromium-browse | while read -r p; do grep -qzF "$work/profile" "/proc/$p/cmdline" 2>/dev/null && echo x; done | grep -q x; }
quit_chromium() { close_all chromium-browser; close_all ''; until_ok 10000 chromium_gone; }

# Before the theme was ever rendered the extension folder is missing, and Chromium still starts.
chromium "$work/never-rendered"
error_up() { niri msg -j windows | jq -e 'any(.[]; .title == "Error Loading Extension")' >/dev/null; }
until_ok 15000 error_up
grim -s 1 "$work/chromium-missing.png"
echo "windows with the extension missing: $(niri msg -j windows | jq -c '[.[] | .title]')"
niri msg action focus-window --id "$(niri msg -j windows | jq -r 'first(.[] | select(.title == "Error Loading Extension") | .id)')"
wtype -k Return
until_ok 15000 chromium_up
check "Chromium starts with no rendered extension, once its error is dismissed" chromium_up
quit_chromium
# The first start with the extension installs it and says so once; the measured start is the one after.
chromium "$out/chromium-theme"
until_ok 15000 chromium_up
sleep 8
quit_chromium
"$repo/bin/dots" theme blueprint
chromium "$out/chromium-theme"
until_ok 15000 chromium_up
sleep 2
grim -s 1 "$work/chromium-blueprint.png"
# niri's geometry for Chromium takes in its shadow, so the page is found by its magenta and the chrome is read upward from its top-left: colour runs, nearest first.
chrome=$(grim -s 1 -t ppm - | node -e '
  const b = require("fs").readFileSync(0);
  const head = b.toString("latin1").match(/^P6\s+(\d+)\s+(\d+)\s+(\d+)\s/);
  const w = +head[1], h = +head[2], px = b.subarray(head[0].length);
  const at = (x, y) => { const i = (y * w + x) * 3; return "#" + [px[i], px[i + 1], px[i + 2]].map((v) => v.toString(16).padStart(2, "0")).join(""); };
  let top = -1, left = -1;
  for (let y = 0; y < h && top < 0; y++) for (let x = 0; x < w; x++) if (at(x, y) === "#ff00ff") { top = y; left = x; break; }
  const runs = [];
  for (let y = top - 1; top > 0 && y >= Math.max(0, top - 160); y--) {
    const c = at(left + 10, y);
    if (runs.length && runs[runs.length - 1][0] === c) runs[runs.length - 1][1]++; else runs.push([c, 1]);
  }
  // A bubble hangs over the page from the toolbar, so the page top must be magenta wall to wall.
  let right = left;
  while (right + 1 < w && at(right + 1, top) === "#ff00ff") right++;
  let covered = 0;
  for (let y = top; top > 0 && y < Math.min(h, top + 200); y++) for (let x = left; x <= right; x++) if (at(x, y) !== "#ff00ff") covered++;
  console.log(JSON.stringify({ runs, width: right - left + 1, covered }));
')
echo "Chromium's chrome above the page, nearest first: $chrome"
# Nearest the page comes the toolbar, about 40 px, then the frame; an infobar or bubble under the toolbar doubles its band.
bands() { jq -c '[.runs[] | select(.[1] >= 10)]' <<<"$chrome"; }
check "Chromium's toolbar is Blueprint's surface #0a1526 exactly, with no bar or bubble under it ($(bands))" jq -e '[.runs[] | select(.[1] >= 10)] | .[0][0] == "#0a1526" and .[0][1] >= 20 and .[0][1] <= 60' <<<"$chrome"
check "above it Chromium's frame is Blueprint's paper #0c1a2e exactly" jq -e '[.runs[] | select(.[1] >= 10)] | .[1][0] == "#0c1a2e"' <<<"$chrome"
check "no bubble covers the page's top ($(jq -c '{width, covered}' <<<"$chrome"))" jq -e '.width >= 400 and .covered == 0' <<<"$chrome"
check "Chromium opened no other window ($(niri msg -j windows | jq -c '[.[] | .title]'))" test "$(niri msg -j windows | jq length)" = 1
quit_chromium

# A failed look leaves its screenshots for the reader.
((fails > 0)) && cp "$work"/*.png "${DOTS_CHECK_SHOTS:-/tmp}/" 2>/dev/null
exit $((fails > 0))
}
