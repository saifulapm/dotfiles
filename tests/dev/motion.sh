#!/usr/bin/env bash
# The one design's window open and close shaders, seen at slowdown 20 in the pixels of a plain magenta foot with no frame: it inks in along the diagonal at its own size.
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

artboard() {
  local x y w h t
  check "niri compiles the spring's shaders" no_shader_errors "$log_line"
  check "a resting magenta window is found" calibrate
  [ -n "$box" ] || return
  read -r x y w h <<<"$box"
  # The focused window is square in its 1 px edge: the pixel left and right of its magenta is Artboard's line #D0D7DE, the dots' colour, and its top corners are magenta, no desk showing round a radius.
  local corner='
    const line = (c) => near(c, [208, 215, 222], 8);
    let x0 = w, y0 = h, x1 = -1;
    for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) if (magenta(at(x, y))) { x0 = Math.min(x0, x); x1 = Math.max(x1, x); y0 = Math.min(y0, y); }
    return x1 >= 0 && line(at(x0 - 1, y0 + 20)) && line(at(x1 + 1, y0 + 20)) && magenta(at(x0, y0)) && magenta(at(x1, y0));'
  open_magenta
  wait_until 1000
  t=$(($(now_ms) - t0))
  # Half way along its ease the ink's soft edge crosses the middle: the top-left corner is in, the bottom-right not yet, and the window is at its own place and size.
  check "$t ms into its open (50 ms real): inked at the top left, not yet at the bottom right, at its own size" \
    grab_test "$x,$y ${w}x$h" "
      return magenta(at(4, 4)) && !magenta(at(w - 5, h - 5));"
  sleep 4
  check "at rest: square corners in the focused 1 px edge" grab_test "$((x - 40)),$((y - 40)) $((w + 80))x$((h / 2))" "$corner"
  close_window
  until_ok 8000 has_windows 0
}

artboard

# The broken fixture: a syntax error in an open shader must turn the check above red; it is an include of its own, since niri merges a second animations block only from one.
broken() {
  printf 'animations {\n    window-open {\n        custom-shader r"\n            vec4 open_color(vec3 coords_geo, vec3 size_geo) { return vec4(1.0) +; }\n        "\n    }\n}\n' >"$DOTS_DEV_DIR/broken.kdl"
  printf 'include "broken.kdl"\n' >>"$DOTS_DEV_DIR/niri.kdl"
}
reload broken
check "a shader with a syntax error fails the compile check" eval "! no_shader_errors $log_line"
exit "$fails"
}
