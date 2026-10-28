#!/usr/bin/env bash
# screen shot covers the focused output and prints its name in JSON, 1280 px wide; --output with a name niri lacks exits 2 naming the ones it has; a point read off the shot lands there: a click at the centre of a red button found in shot.png presses that button and none of its eight neighbours.
{
source "$(dirname "$0")/lib.sh"

dots_pointer_build || exit 1
scripts=$repo/home/dot_claude/skills/desktop/scripts
has_window() { niri msg -j windows | jq -e ".[] | select(.app_id == \"$1\")" >/dev/null; }
name=$(niri msg -j focused-output | jq -r .name)

out=$("$scripts/screen" shot)
check "screen shot prints the focused output's name ($name): $out" bash -c "jq -e '.output == \"$name\" and .width == 1280 and .shot == \"/tmp/desk/shot.png\"' <<<'$out' >/dev/null"
check "and the file is 1280 px wide" bash -c "file /tmp/desk/shot.png | grep -q ', 1280 x '"
out=$("$scripts/screen" shot --output "$name")
check "screen shot --output $name shoots it" bash -c "jq -e '.output == \"$name\"' <<<'$out' >/dev/null"
err=$("$scripts/screen" shot --output nope 2>&1 >/dev/null)
rc=$?
check "screen shot --output nope exits 2 (got $rc)" test "$rc" = 2
check "naming the outputs there are: $err" bash -c "grep -q -- '$name' <<<'$err'"

# Nine buttons in a grid, the middle one red; each writes its own name when pressed.
cat >"$DOTS_DEV_DIR/grid.py" <<PY
import gi
gi.require_version("Gtk", "4.0")
from gi.repository import Gdk, GLib, Gtk
GLib.set_prgname("grid")
def activate(app):
    css = Gtk.CssProvider()
    css.load_from_string("button { min-width: 40px; min-height: 30px; } #target { background: #ff0000; background-image: none; }")
    Gtk.StyleContext.add_provider_for_display(Gdk.Display.get_default(), css, 800)
    w = Gtk.ApplicationWindow(application=app, title="grid")
    g = Gtk.Grid(column_spacing=6, row_spacing=6)
    for i in range(9):
        b = Gtk.Button(label="")
        if i == 4:
            b.set_name("target")
        b.connect("clicked", lambda _, i=i: open("$DOTS_DEV_DIR/pressed", "a").write(f"{i}\n"))
        g.attach(b, i % 3, i // 3, 1, 1)
    w.set_child(g)
    w.present()
app = Gtk.Application(application_id="org.dots.Grid")
app.connect("activate", activate)
app.run([])
PY
"$scripts/screen" launch python3 "$DOTS_DEV_DIR/grid.py" >/dev/null
until_ok 5000 has_window org.dots.Grid
id=$(niri msg -j windows | jq '.[] | select(.app_id == "org.dots.Grid") | .id')
niri msg action toggle-window-floating --id "$id"
niri msg action move-floating-window --id "$id" -x 333 -y 217
sleep 1

# The red box's centre, read from the PNG screen shot wrote.
red_centre() {
  python3 - /tmp/desk/shot.png <<'PY'
import struct, sys, zlib
data = open(sys.argv[1], "rb").read()
pos, idat = 8, b""
while pos < len(data):
    n, kind = struct.unpack(">I4s", data[pos:pos + 8])
    body = data[pos + 8:pos + 8 + n]
    if kind == b"IHDR":
        w, h, depth, colour = struct.unpack(">IIBB", body[:10])
    elif kind == b"IDAT":
        idat += body
    pos += 12 + n
bpp = {2: 3, 6: 4}[colour]
raw, rows, prev = zlib.decompress(idat), [], bytearray(w * bpp)
for y in range(h):
    f, line = raw[y * (w * bpp + 1)], bytearray(raw[y * (w * bpp + 1) + 1:(y + 1) * (w * bpp + 1)])
    for i in range(len(line)):
        a = line[i - bpp] if i >= bpp else 0
        b, c = prev[i], prev[i - bpp] if i >= bpp else 0
        p = a + b - c
        pred = [0, a, b, (a + b) // 2, a if abs(p - a) <= abs(p - b) and abs(p - a) <= abs(p - c) else b if abs(p - b) <= abs(p - c) else c][f]
        line[i] = (line[i] + pred) & 255
    rows.append(line)
    prev = line
xs, ys = [], []
for y, line in enumerate(rows):
    for x in range(w):
        r, g, b = line[x * bpp:x * bpp + 3]
        if r > 220 and g < 40 and b < 40:
            xs.append(x); ys.append(y)
print((min(xs) + max(xs)) // 2, (min(ys) + max(ys)) // 2, max(xs) - min(xs) + 1, max(ys) - min(ys) + 1) if xs else print("none")
PY
}
"$scripts/screen" shot >/dev/null
read -r cx cy bw bh < <(red_centre)
check "the shot shows the red button ($bw x $bh px at $cx,$cy)" test -n "${bh:-}"
out=$("$scripts/screen" click "$cx" "$cy")
rc=$?
check "screen click at its centre exits 0 (got $rc: $out)" test "$rc" = 0
pressed_middle() { [ "$(cat "$DOTS_DEV_DIR/pressed" 2>/dev/null)" = 4 ]; }
check "and presses the red button, none of its neighbours ($(cat "$DOTS_DEV_DIR/pressed" 2>/dev/null | tr '\n' ' '))" until_ok 2000 pressed_middle

exit $((fails > 0))
}
