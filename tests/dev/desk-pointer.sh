#!/usr/bin/env bash
# The desktop skill's screen and mouse drive the pointer through dots-pointer alone: a screen drag moves a widget-factory scale and a scroll turns another, as gui reads them, a move to (0,0) lands at (2,2), and neither ydotool nor wlrctl runs.
{
source "$(dirname "$0")/lib.sh"

dots_pointer_build || exit 1
scripts=$repo/home/dot_claude/skills/desktop/scripts
# ydotool and wlrctl, first on PATH, log any call and fail, so a pointer path still using them shows.
stub=$DOTS_DEV_DIR/stubs
mkdir -p "$stub"
for t in ydotool wlrctl; do
  printf '#!/bin/sh\necho "%s $*" >>"%s/calls"\nexit 1\n' "$t" "$stub" >"$stub/$t"
  chmod +x "$stub/$t"
done
PATH=$stub:$PATH

# niri's hot corner is bottom-left and fires only with no fullscreen window, so this runs before any window opens.
overview_is() { niri msg -j overview-state | jq -e ".is_open == $1" >/dev/null; }
read -r ow oh < <(niri msg -j outputs | jq -r '[.[] | .logical][0] | "\(.width) \(.height)"')
"$scripts/mouse" to 0 "$((oh * 4))"
sleep 0.3
check "a mouse move into the bottom-left hot corner stops short of it: the overview stays closed" overview_is false
# The same corner reached exactly opens it, so the check above can fail.
dots-pointer "0,0,$ow,$oh" move 0 $((oh - 1))
check "while dots-pointer at the corner itself opens the overview" until_ok 1000 overview_is true
niri msg action close-overview
until_ok 2000 overview_is false

niri msg action spawn -- gtk4-widget-factory
factory() { niri msg -j windows | jq -r '.[] | select(.app_id == "org.gtk.WidgetFactory4") | .id'; }
factory_up() { [ -n "$(factory)" ]; }
until_ok 8000 factory_up
id=$(factory)
# Fullscreen puts the window's origin at (0,0), so GTK's window-relative extents are logical pixels.
niri msg action fullscreen-window --id "$id"
fullscreen() { niri msg -j windows | jq -e ".[] | select(.id == $id) | .layout.window_size == [$(niri msg -j outputs | jq -r '[.[] | .logical | .width, .height] | join(",")')]" >/dev/null; }
until_ok 3000 fullscreen

# The Nth horizontal slider as "x y w h value", from AT-SPI with window-relative extents.
slider() {
  python3 - "$1" <<'EOF'
import sys, warnings
warnings.filterwarnings("ignore")
import gi
gi.require_version("Atspi", "2.0")
from gi.repository import Atspi
Atspi.init()
d = Atspi.get_desktop(0)
found = []
def walk(n):
    try:
        if n.get_role_name() == "slider":
            e = Atspi.Component.get_extents(n.get_component(), Atspi.CoordType.WINDOW)
            if e.width > e.height:
                found.append(f"{e.x} {e.y} {e.width} {e.height} {n.get_value().get_current_value():g}")
        for i in range(n.get_child_count()):
            walk(n.get_child_at_index(i))
    except Exception:
        pass
for i in range(d.get_child_count()):
    a = d.get_child_at_index(i)
    if a.get_name() == "gtk4-widget-factory":
        walk(a)
print(found[int(sys.argv[1])] if len(found) > int(sys.argv[1]) else "")
EOF
}
has_slider() { [ -n "$(slider 0)" ]; }
until_ok 8000 has_slider
read -r sx sy sw sh before < <(slider 0)
read -r tx ty tw th turned < <(slider 1)
echo "     slider 0 at $sx,$sy ${sw}x$sh = $before; slider 1 at $tx,$ty = $turned"

# Screen drags and scrolls in shot pixels, the scale screen shot recorded.
"$scripts/screen" shot >/dev/null
shot_px() { echo $(($1 * 1280 / ow)); }
cx=$((sx + sw / 2)) cy=$((sy + sh / 2))
"$scripts/screen" drag "$(shot_px "$cx")" "$(shot_px "$cy")" "$(shot_px $((cx + sw / 3)))" "$(shot_px "$cy")"
moved() { read -r _ _ _ _ v < <(slider 0); [ "$v" != "$before" ] && awk -v v="$v" -v b="$before" 'BEGIN { exit !(v > b) }'; }
check "screen drag of the first scale's slider raises its value from $before" until_ok 2000 moved
read -r _ _ _ _ now < <(slider 0)
check "and gui reads its new value, $now" bash -c "'$scripts/gui' find gtk4-widget-factory slider | head -1 | grep -q '= $now '"
"$scripts/screen" scroll "$(shot_px $((tx + tw / 2)))" "$(shot_px $((ty + th / 2)))" down 3
turned_now() { read -r _ _ _ _ v < <(slider 1); [ "$v" != "$turned" ]; }
check "screen scroll over the second scale turns it from $turned" until_ok 2000 turned_now

# A window that reports where the pointer is, entering or moving: fullscreen, so its surface starts at (0,0).
python3 - "$DOTS_DEV_DIR/where" <<'EOF' &
import sys, gi
gi.require_version("Gtk", "4.0")
from gi.repository import Gtk
def on_motion(_, x, y):
    open(sys.argv[1], "w").write(f"{round(x)} {round(y)}\n")
def activate(app):
    w = Gtk.ApplicationWindow(application=app, title="where")
    m = Gtk.EventControllerMotion()
    m.connect("enter", on_motion)
    m.connect("motion", on_motion)
    w.add_controller(m)
    w.fullscreen()
    w.present()
app = Gtk.Application(application_id="org.dots.Where")
app.connect("activate", activate)
app.run([])
EOF
where=$!
cleanup() { kill "$where" 2>/dev/null; }
where_id() { niri msg -j windows | jq -r '.[] | select(.title == "where") | .id'; }
where_up() { [ -n "$(where_id)" ]; }
until_ok 5000 where_up
niri msg action focus-window --id "$(where_id)"
where_shown() { niri msg -j focused-window | jq -e '.title == "where" and .layout.window_size[0] > 1000' >/dev/null; }
until_ok 3000 where_shown
"$scripts/mouse" to 300 300
at() { [ "$(cat "$DOTS_DEV_DIR/where" 2>/dev/null)" = "$1" ]; }
check "mouse to 300 300 lands at (300,300)" until_ok 2000 at "300 300"
"$scripts/mouse" to 0 0
check "mouse to 0 0 lands at (2,2), off the corner" until_ok 2000 at "2 2"

check "neither ydotool nor wlrctl ran" test ! -e "$stub/calls"
[ -e "$stub/calls" ] && head -3 "$stub/calls"

exit $((fails > 0))
}
