#!/usr/bin/env bash
# Each theme's window open and close shaders, seen at slowdown 20 in the pixels of a plain magenta foot.
{
source "$(dirname "$0")/lib.sh"

# niri logs each config it loads, and a shader that does not compile only as a warning after it.
loads() { grep -ac 'loaded config from' "$dev_log"; }
loads_past() { (($(loads) > $1)); }
no_shader_errors() { ! tail -n +"$1" "$dev_log" | grep -aq 'error compiling custom'; }
# Runs a command that changes the config, then waits for niri to load it and compile its shaders.
reload() {
  local n
  n=$(loads) log_line=$(($(wc -l <"$dev_log") + 1))
  "$@" || return 1
  until_ok 3000 loads_past "$n" || return 1
  sleep 0.3
}

# Slowed only here: no rendered fragment carries a slowdown.
slow() { printf 'animations {\n    slowdown 20\n}\n' >>"$DOTS_DEV_DIR/niri.kdl"; }
check "niri loads the slowdown" reload slow

window_count() { niri msg -j windows | jq length; }
has_windows() { [ "$(window_count)" = "$1" ]; }

# Opens the magenta foot, its cursor hidden, and sets t0 to the moment niri lists it, which is when its open starts.
t0=0
open_magenta() {
  niri msg action spawn -- foot -c /dev/null -o colors-dark.background=ff00ff -o colors-light.background=ff00ff \
    sh -c 'printf "\033[?25l"; exec sleep 600' >/dev/null
  until_ok 5000 has_windows 1 || return 1
  t0=$(now_ms)
}
close_window() {
  t0=$(now_ms)
  niri msg action close-window
}
wait_until() { while (($(now_ms) - t0 < $1)); do sleep 0.005; done; }

# Runs a pixel test on a grab of x,y wxh: node gets the PPM's width, height and RGB bytes as w, h and px.
grab_test() {
  local g=$1
  shift
  grim -t ppm -g "$g" - | node -e '
    const b = require("fs").readFileSync(0);
    const head = b.toString("latin1").match(/^P6\s+(\d+)\s+(\d+)\s+(\d+)\s/);
    const w = +head[1], h = +head[2], px = b.subarray(head[0].length);
    const at = (x, y) => [...px.subarray((y * w + x) * 3, (y * w + x) * 3 + 3)];
    const near = (c, t, d = 16) => c.every((v, i) => Math.abs(v - t[i]) <= d);
    const magenta = (c) => c[0] - c[1] > 60 && c[2] - c[1] > 60;
    const ok = (function () { '"$1"' }());
    process.exit(ok ? 0 : 1);
  ' "${@:2}"
}

# The magenta's box at rest, as "x y w h", from a full grab once its open is over.
rest_box() {
  grim -t ppm - | node -e '
    const b = require("fs").readFileSync(0);
    const head = b.toString("latin1").match(/^P6\s+(\d+)\s+(\d+)\s+(\d+)\s/);
    const w = +head[1], h = +head[2], px = b.subarray(head[0].length);
    let x0 = w, y0 = h, x1 = -1, y1 = -1;
    for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
      const i = (y * w + x) * 3;
      if (px[i] - px[i + 1] > 60 && px[i + 2] - px[i + 1] > 60) { x0 = Math.min(x0, x); x1 = Math.max(x1, x); y0 = Math.min(y0, y); y1 = Math.max(y1, y); }
    }
    console.log(x1 < 0 ? "" : `${x0} ${y0} ${x1 - x0 + 1} ${y1 - y0 + 1}`);
  '
}

# A first open and close finds where the window rests, so the timed grabs need no layout maths; check always returns 0, so a failed one is skipped by its empty box.
calibrate() {
  box=
  open_magenta || return 1
  sleep 6
  box=$(rest_box)
  close_window
  until_ok 8000 has_windows 0
  sleep 4
  [ -n "$box" ]
}

switch_to() { "$repo/bin/dots" theme "$1" >/dev/null; }
theme() {
  check "niri loads $1's fragment" reload switch_to "$1"
  check "niri compiles $1's shaders" no_shader_errors "$log_line"
}

blueprint() {
  local x y w h t
  theme blueprint
  check "blueprint: a resting magenta window is found" calibrate
  [ -n "$box" ] || return
  read -r x y w h <<<"$box"
  # niri's 1 px border sits just outside foot's surface, so the outline runs one row above the magenta.
  open_magenta
  wait_until 1320
  t=$(($(now_ms) - t0))
  check "blueprint 30% into its open ($t ms of 4400): accent along its top edge" \
    grab_test "$x,$((y - 1)) ${w}x1" 'let n = 0; for (let i = 0; i < w; i++) if (near(at(i, 0), [127, 227, 240])) n++; return n >= w * 0.9;'
  check "blueprint 30% into its open: paper colour at its centre" \
    grab_test "$((x + w / 2)),$((y + h / 2)) 1x1" 'return near(at(0, 0), [12, 26, 46]);'
  sleep 4
  close_window
  wait_until 2560
  t=$(($(now_ms) - t0))
  check "blueprint 80% into its close ($t ms of 3200): outline pixels and none of its content" \
    grab_test "$((x - 1)),$((y - 1)) $((w + 2))x$((h + 2))" '
      let pen = 0;
      for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) { const c = at(x, y); if (magenta(c)) return false; if (near(c, [127, 227, 240])) pen++; }
      return pen > 100;'
  until_ok 8000 has_windows 0
}

paper() {
  local x y w h t
  theme paper
  check "paper: a resting magenta window is found" calibrate
  [ -n "$box" ] || return
  read -r x y w h <<<"$box"
  open_magenta
  # The drop is 3 px or more only until about 400 ms, and the grab lands up to 50 ms after the wait.
  wait_until 250
  t=$(($(now_ms) - t0))
  # A column through the top edge, from 16 px above the resting top: the magenta starts 3 px or more higher, and is pure.
  check "paper $t ms into its open (of 2800): its top 3 px or more above rest, fully opaque" \
    grab_test "$((x + w / 2)),$((y - 16)) 1x40" '
      let top = -1; for (let i = 0; i < h; i++) if (magenta(at(0, i))) { top = i; break; }
      return top >= 0 && top <= 13 && near(at(0, top + 10), [255, 0, 255], 4);'
  sleep 4
  # The workspaces slide over niri's overview backdrop, so a gap between them shows its colour.
  niri msg action focus-workspace-down
  sleep 0.3
  check "paper mid workspace switch: no band of niri's grey backdrop" \
    grab_test "$((x + w / 2)),0 1x$((y + h + 28))" 'for (let i = 0; i < h; i++) if (near(at(0, i), [38, 38, 38], 8)) return false; return true;'
  niri msg action focus-workspace-up
  sleep 4
  close_window
  wait_until 1000
  t=$(($(now_ms) - t0))
  check "paper 50% into its close ($t ms of 2000): at most its top 40%, and paper where its bottom half was" \
    grab_test "$((x + w / 2)),$y 1x$h" '
      let shown = 0;
      for (let i = 0; i < h; i++) if (magenta(at(0, i))) { if (i >= h * 0.4) return false; shown++; }
      if (!shown) return false;
      for (let i = Math.ceil(h / 2); i < h; i++) if (!near(at(0, i), [241, 233, 216], 30)) return false;
      return true;'
  until_ok 8000 has_windows 0
}

artboard() {
  local x y w h t
  theme artboard
  check "artboard: a resting magenta window is found" calibrate
  [ -n "$box" ] || return
  read -r x y w h <<<"$box"
  # The magenta's own box corner lies outside the 14 px radius and its 2 px ring, so it reads the paper's grey (a dot or the shadow may darken it), never magenta or the blue ring.
  local corner='
    const grey = (c) => Math.max(...c) - Math.min(...c) < 24;
    let x0 = w, y0 = h, x1 = -1;
    for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) if (magenta(at(x, y))) { x0 = Math.min(x0, x); x1 = Math.max(x1, x); y0 = Math.min(y0, y); }
    return x1 >= 0 && grey(at(x0, y0)) && grey(at(x1, y0));'
  open_magenta
  wait_until 1000
  t=$(($(now_ms) - t0))
  # niri's own open starts at half size, so the 96% floor tells Artboard's apart.
  check "artboard $t ms into its open (50 ms real): 2% to 4% narrower than at rest" \
    grab_test "$((x - 40)),$((y + h / 2)) $((w + 80))x1" "
      let n = 0; for (let i = 0; i < w; i++) if (magenta(at(i, 0))) n++;
      return n >= $w * 0.96 - 1 && n <= $w * 0.98;"
  check "artboard mid-open: its corners outside the radius read the paper's grey" grab_test "$((x - 40)),$((y - 40)) $((w + 80))x$((h / 2))" "$corner"
  sleep 4
  check "artboard at rest: its corners outside the radius read the paper's grey" grab_test "$((x - 40)),$((y - 40)) $((w + 80))x$((h / 2))" "$corner"
  close_window
  until_ok 8000 has_windows 0
}

# Runs a pixel test on PPM grabs saved to files: node gets them as g[0], g[1] and on, each with w, h and at(x, y).
ppm_test() {
  node -e '
    const g = process.argv.slice(1).map((f) => {
      const b = require("fs").readFileSync(f);
      const head = b.toString("latin1").match(/^P6\s+(\d+)\s+(\d+)\s+(\d+)\s/);
      const w = +head[1], h = +head[2], px = b.subarray(head[0].length);
      return { w, h, at: (x, y) => [...px.subarray((y * w + x) * 3, (y * w + x) * 3 + 3)] };
    });
    const near = (c, t, d = 16) => c.every((v, i) => Math.abs(v - t[i]) <= d);
    const magenta = (c) => c[0] - c[1] > 60 && c[2] - c[1] > 60;
    const amber = (c) => c[0] - c[2] >= 15;
    const ok = (function () { '"$1"' }());
    process.exit(ok ? 0 : 1);
  ' "${@:2}"
}

# Each magenta window's box on screen, one "x y w h" a line, left to right.
magenta_boxes() {
  grim -t ppm - | node -e '
    const b = require("fs").readFileSync(0);
    const head = b.toString("latin1").match(/^P6\s+(\d+)\s+(\d+)\s+(\d+)\s/);
    const w = +head[1], h = +head[2], px = b.subarray(head[0].length);
    const boxes = [];
    let cur = null;
    for (let x = 0; x < w; x++) {
      let y0 = -1, y1 = -1;
      for (let y = 0; y < h; y++) {
        const i = (y * w + x) * 3;
        if (px[i] - px[i + 1] > 60 && px[i + 2] - px[i + 1] > 60) { if (y0 < 0) y0 = y; y1 = y; }
      }
      if (y0 < 0) { cur = null; continue; }
      if (!cur) { cur = { x0: x, x1: x, y0, y1 }; boxes.push(cur); }
      cur.x1 = x;
      cur.y0 = Math.min(cur.y0, y0);
      cur.y1 = Math.max(cur.y1, y1);
    }
    for (const c of boxes) console.log(`${c.x0} ${c.y0} ${c.x1 - c.x0 + 1} ${c.y1 - c.y0 + 1}`);
  '
}

hifi() {
  local x y w h t g m=30 dir=$DOTS_DEV_DIR/hifi
  theme hi-fi
  check "hi-fi: a resting magenta window is found" calibrate
  [ -n "$box" ] || return
  read -r x y w h <<<"$box"
  mkdir -p "$dir"
  # The grabs take the window and 30 px round it, past the glow's 24 px, so the magenta starts at (30, 30) in each.
  g="$((x - m)),$((y - m)) $((w + 2 * m))x$((h + 2 * m))"
  grim -t ppm -g "$g" "$dir/before.ppm"
  open_magenta
  wait_until 1320
  grim -t ppm -g "$g" "$dir/open30.ppm"
  wait_until 2200
  grim -t ppm -g "$g" "$dir/open50.ppm"
  wait_until 3080
  t=$(($(now_ms) - t0))
  grim -t ppm -g "$g" "$dir/open70.ppm"
  wait_until 3960
  grim -t ppm -g "$g" "$dir/open90.ppm"
  # The border ring, a row above the magenta, is held back with the glow until the open's last 60 of 220 ms (3200 ms here).
  check "hi-fi's border and glow come up late in its open: not amber at 50%, amber at 90%" \
    ppm_test "
      let mid = 0, late = 0;
      for (let i = 0; i < $w; i++) { if (amber(g[0].at($m + i, $m - 1))) mid++; if (amber(g[1].at($m + i, $m - 1))) late++; }
      return mid < $w * 0.1 && late >= $w * 0.9;" \
    "$dir/open50.ppm" "$dir/open90.ppm"
  # Against the dark paper, a dimmer magenta has less red and blue.
  check "hi-fi 30% into its open is darker than at 70% ($t ms of 4400)" \
    ppm_test "const a = g[0].at($m + $w / 2 | 0, $m + $h / 2 | 0), b = g[1].at($m + $w / 2 | 0, $m + $h / 2 | 0); return a[0] + a[2] < b[0] + b[2];" \
    "$dir/open30.ppm" "$dir/open70.ppm"
  check "hi-fi 70% into its open: the magenta sits in its rest box, unscaled and unmoved" \
    ppm_test "
      const o = g[0]; let x0 = o.w, y0 = o.h, x1 = -1, y1 = -1;
      for (let y = 0; y < o.h; y++) for (let x = 0; x < o.w; x++) if (magenta(o.at(x, y))) { x0 = Math.min(x0, x); x1 = Math.max(x1, x); y0 = Math.min(y0, y); y1 = Math.max(y1, y); }
      return [x0 - $m, y0 - $m, x1 - $m - $w + 1, y1 - $m - $h + 1].every((d) => Math.abs(d) <= 1);" \
    "$dir/open70.ppm"
  sleep 3
  close_window
  wait_until 2240
  t=$(($(now_ms) - t0))
  grim -t ppm -g "$g" "$dir/close80.ppm"
  # niri's 1 px border sits just outside foot's surface, so the geometry's edge, and the outline, is one row above the magenta.
  check "hi-fi 80% into its close ($t ms of 2800): an amber outline round paper" \
    ppm_test "
      const c = g[0], p = g[1];
      let n = 0; for (let i = 0; i < $w; i++) if (amber(c.at($m + i, $m - 1))) n++;
      if (n < $w * 0.9) return false;
      const cx = $m + $w / 2 | 0, cy = $m + $h / 2 | 0;
      return near(c.at(cx, cy), p.at(cx, cy), 6);" \
    "$dir/close80.ppm" "$dir/before.ppm"
  until_ok 8000 has_windows 0
  sleep 1
  grim -t ppm -g "$g" "$dir/after.ppm"
  check "hi-fi after its close: only the paper where it was" \
    ppm_test "for (let y = 0; y < g[0].h; y++) for (let x = 0; x < g[0].w; x++) if (!near(g[0].at(x, y), g[1].at(x, y), 6)) return false; return true;" \
    "$dir/after.ppm" "$dir/before.ppm"
  # Each window warms up on its own progress, so two opened 50 ms apart both end whole, and the focused one glows.
  niri msg action spawn -- foot -c /dev/null -o colors-dark.background=ff00ff -o colors-light.background=ff00ff \
    sh -c 'printf "\033[?25l"; exec sleep 600' >/dev/null
  sleep 0.05
  niri msg action spawn -- foot -c /dev/null -o colors-dark.background=ff00ff -o colors-light.background=ff00ff \
    sh -c 'printf "\033[?25l"; exec sleep 600' >/dev/null
  until_ok 5000 has_windows 2
  sleep 6
  magenta_boxes >"$dir/boxes"
  grim -t ppm "$dir/two.ppm"
  # The focused one has the amber border a row above its top, and its glow a few rows above that; the other's border is #3C3836 and its shadow transparent.
  check "hi-fi: two windows opened 50 ms apart both end opaque, the focused one with its glow" \
    ppm_test "
      const boxes = require('fs').readFileSync('$dir/boxes', 'utf8').trim().split('\n').filter(Boolean).map((l) => l.split(' ').map(Number));
      if (boxes.length !== 2) return false;
      const s = g[0]; let lit = 0;
      for (const [bx, by, bw, bh] of boxes) {
        if (!near(s.at(bx + (bw >> 1), by + (bh >> 1)), [255, 0, 255], 4)) return false;
        if (!amber(s.at(bx + (bw >> 1), by - 1))) continue;
        let n = 0; for (let i = bw >> 2; i < (3 * bw) >> 2; i++) if (amber(s.at(bx + i, by - 3))) n++;
        if (n >= (bw >> 1) * 0.9) lit++;
      }
      return lit === 1;" \
    "$dir/two.ppm"
  niri msg action close-window
  niri msg action focus-column-left
  niri msg action close-window
  until_ok 8000 has_windows 0
}

# At output scale 1.25 the power-off's outline must still be one physical pixel: a pen measured in logical px would land on a fraction and blur into two rows.
hifi_scaled() {
  local name x y w h dir=$DOTS_DEV_DIR/hifi
  mkdir -p "$dir"
  name=$(niri msg -j outputs | jq -r 'first(.[]).name')
  niri msg output "$name" scale 1.25
  scaled() { niri msg -j outputs | jq -e 'first(.[]).logical.scale == 1.25' >/dev/null; }
  check "hi-fi: the nested output $name takes scale 1.25" until_ok 3000 scaled
  # rest_box grabs with no -s, so the box is in physical pixels.
  check "hi-fi at 1.25: a resting magenta window is found" calibrate
  [ -n "$box" ] || return
  read -r x y w h <<<"$box"
  open_magenta
  sleep 6
  close_window
  wait_until 2240
  grim -t ppm "$dir/scaled80.ppm"
  # From four rows above the magenta's top to two rows into it (its content is all but gone by now), across its middle half: exactly one row is amber along its length, and none is half-lit, as a line blurred over two rows would be.
  check "hi-fi at 1.25, 80% into its close: the outline above the window is one physical row" \
    ppm_test "
      const s = g[0]; const rows = [];
      for (let r = 4; r >= -2; r--) { let n = 0; for (let i = $w >> 2; i < (3 * $w) >> 2; i++) if (amber(s.at($x + i, $y - r))) n++; rows.push(n / ($w >> 1)); }
      console.error('     amber share of the rows from 4 above the window to 2 into it:', rows.map((v) => v.toFixed(2)).join(' '));
      return rows.filter((v) => v >= 0.9).length === 1 && rows.every((v) => v >= 0.9 || v <= 0.1);" \
    "$dir/scaled80.ppm"
  until_ok 8000 has_windows 0
}

blueprint
paper
artboard
hifi
hifi_scaled

# The broken fixture: a syntax error in an open shader must turn the check above red; it is an include of its own, since niri merges a second animations block only from one.
broken() {
  printf 'animations {\n    window-open {\n        custom-shader r"\n            vec4 open_color(vec3 coords_geo, vec3 size_geo) { return vec4(1.0) +; }\n        "\n    }\n}\n' >"$DOTS_DEV_DIR/broken.kdl"
  printf 'include "broken.kdl"\n' >>"$DOTS_DEV_DIR/niri.kdl"
}
reload broken
check "a shader with a syntax error fails the compile check" eval "! no_shader_errors $log_line"
exit "$fails"
}
