#!/usr/bin/env bash
# Each theme's window open and close shaders, seen at slowdown 20 in the pixels of a plain magenta foot.
{
source "$(dirname "$0")/lib.sh"

# Slowed only here: no rendered fragment carries a slowdown.
printf 'animations {\n    slowdown 20\n}\n' >>"$DOTS_DEV_DIR/niri.kdl"

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
    const args = process.argv.slice(1);
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

# A first open and close finds where the window rests, so the timed grabs need no layout maths.
calibrate() {
  open_magenta || return 1
  sleep 6
  box=$(rest_box)
  close_window
  until_ok 8000 has_windows 0
  sleep 4
  [ -n "$box" ]
}

theme() {
  "$repo/bin/dots" theme "$1" >/dev/null
  # niri reloads the fragment on its own watch; the next open must already use it.
  sleep 1
}

blueprint() {
  local x y w h t
  theme blueprint
  check "blueprint: a resting magenta window is found" calibrate || return
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
  check "paper: a resting magenta window is found" calibrate || return
  read -r x y w h <<<"$box"
  open_magenta
  wait_until 300
  t=$(($(now_ms) - t0))
  # A column through the top edge, from 16 px above the resting top: the magenta starts 3 px or more higher, and is pure.
  check "paper $t ms into its open (of 2800): its top 3 px or more above rest, fully opaque" \
    grab_test "$((x + w / 2)),$((y - 16)) 1x40" '
      let top = -1; for (let i = 0; i < h; i++) if (magenta(at(0, i))) { top = i; break; }
      return top >= 0 && top <= 13 && near(at(0, top + 10), [255, 0, 255], 4);'
  sleep 4
  close_window
  wait_until 1000
  t=$(($(now_ms) - t0))
  check "paper 50% into its close ($t ms of 2000): at most its top 40%, and paper where its bottom half was" \
    grab_test "$((x + w / 2)),$y 1x$h" '
      for (let i = 0; i < h; i++) if (magenta(at(0, i)) && i >= h * 0.4) return false;
      for (let i = Math.ceil(h / 2); i < h; i++) if (!near(at(0, i), [241, 233, 216], 30)) return false;
      return true;'
  until_ok 8000 has_windows 0
}

artboard() {
  local x y w h t
  theme artboard
  check "artboard: a resting magenta window is found" calibrate || return
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

blueprint
paper
artboard
exit "$fails"
}
