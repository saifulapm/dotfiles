#!/usr/bin/env bash
# A click lands only over an agent window: over Saiful's foot it exits 3 and his foot keeps neither focus nor its focus_timestamp; over the Island it is refused though an agent window lies beneath; a pick with no answer refuses; over the launched widget factory it presses the button, and a dialog it opens takes keys; gui click works in an agent window and refuses elsewhere.
{
source "$(dirname "$0")/lib.sh"

dots_pointer_build || exit 1
scripts=$repo/home/dot_claude/skills/desktop/scripts
mouse=$scripts/mouse
window_of() { niri msg -j windows | jq -r ".[] | select(.app_id == \"$1\") | .id" | sort -n | tail -1; }
has_window() { [ -n "$(window_of "$1")" ]; }
focused() { niri msg -j focused-window | jq -r .id; }
focus_is() { [ "$(focused)" = "$1" ]; }
focus() { niri msg action focus-window --id "$1" && until_ok 2000 focus_is "$1"; }
stamp() { niri msg -j windows | jq -c ".[] | select(.id == $1) | .focus_timestamp"; }
tile() { niri msg -j windows | jq -r ".[] | select(.id == $1) | .layout.tile_pos_in_workspace_view | map(floor) | join(\" \")"; }
read -r ow oh < <(niri msg -j outputs | jq -r '[.[] | .logical][0] | "\(.width) \(.height)"')

# Saiful's foot floats on the left; the launched factory floats on the right, pushed to the top under the Island.
niri msg action spawn -- foot -c /dev/null -a his
until_ok 5000 has_window his
his=$(window_of his)
niri msg action toggle-window-floating --id "$his"
niri msg action move-floating-window --id "$his" -x 100 -y 300
"$scripts/screen" launch gtk4-widget-factory >/dev/null
until_ok 8000 has_window org.gtk.WidgetFactory4
factory=$(window_of org.gtk.WidgetFactory4)
niri msg action toggle-window-floating --id "$factory"
niri msg action move-floating-window --id "$factory" -x $((ow / 2 - 400)) -y 0
sleep 0.5
focus "$factory"
read -r hx hy < <(tile "$his")
read -r fx fy < <(tile "$factory")
echo "     his foot at $hx,$hy, factory at $fx,$fy"

# Over Saiful's foot: refused, and focus is put back on the factory.
before=$(stamp "$his")
out=$("$mouse" click $((hx + 200)) $((hy + 200)))
rc=$?
check "mouse click over Saiful's foot exits 3 (got $rc)" test "$rc" = 3
check "printing a refusal that names it: $out" bash -c "jq -e '.refused == \"not an agent window\" and .window.id == $his' <<<'$out' >/dev/null"
sleep 1
check "and focus is back on the factory" focus_is "$factory"
check "and his foot's focus_timestamp is unchanged" test "$(stamp "$his")" = "$before"
"$scripts/screen" shot >/dev/null
out=$("$scripts/screen" click $(((hx + 300) * 1280 / ow)) $(((hy + 300) * 1280 / ow)))
check "screen click over his foot is refused the same way" bash -c "jq -e '.window.id == $his' <<<'$out' >/dev/null"
# --any presses there for real, so the checks above can fail.
"$mouse" click $((hx + 200)) $((hy + 200)) left 1 --any
check "while mouse click --any over his foot focuses it" until_ok 1000 focus_is "$his"
focus "$factory"

# Clicks from several agents at once: one gesture runs at a time, so no pick swallows another's press or sends its own for real.
before=$(stamp "$his")
results=$DOTS_DEV_DIR/together
mkdir -p "$results"
clicks=()
for i in 1 2 3 4; do
  "$mouse" click $((hx + 200 + i * 10)) $((hy + 200)) >"$results/his$i" &
  clicks+=($!)
  "$mouse" click $((fx + 300 + i * 10)) $((fy + 300)) >"$results/ours$i" &
  clicks+=($!)
done
# By pid: a bare wait would wait for the nested session lib.sh runs in the background too.
wait "${clicks[@]}"
refusals=$(cat "$results"/his* | jq -s "map(select(.refused == \"not an agent window\" and .window.id == $his)) | length")
check "four clicks over his foot run beside four over the factory: all four refused as his ($refusals)" test "$refusals" = 4
check "and the four over the factory printed no refusal" bash -c "! cat '$results'/ours* | grep -q ."
sleep 1
check "and his foot ends with neither focus nor a new focus_timestamp" bash -c "[ '$(stamp "$his")' = '$before' ] && [ \"\$(niri msg -j focused-window | jq .id)\" != $his ]"
focus "$factory"

# Over the Island, with the factory beneath it: a shell surface takes no clicks.
picked() { dots-pointer "0,0,$ow,$oh" move "$1" "$2" pick | jq -r '.Ok.PickedWindow.id // "null"'; }
island_y=
for y in $(seq $((fy + 1)) $((fy + 60))); do
  if [ "$(picked $((ow / 2 - 150)) "$y")" = "$factory" ] && [ "$(picked $((ow / 2)) "$y")" = null ]; then island_y=$y; break; fi
done
focus "$factory"
check "a row where the factory is picked beside the Island and nothing under it (y=$island_y)" test -n "$island_y"
out=$("$mouse" click $((ow / 2)) "${island_y:-0}")
rc=$?
check "mouse click over the Island exits 3 with no window (got $rc: $out)" bash -c "[ $rc = 3 ] && jq -e '.refused == \"no window\"' <<<'$out' >/dev/null"

# A pick niri never answers: the pointer asks a socket that never replies.
mute=$DOTS_DEV_DIR/mute.sock
python3 -c '
import socket, sys
s = socket.socket(socket.AF_UNIX); s.bind(sys.argv[1]); s.listen(4)
held = []
while True: held.append(s.accept()[0])
' "$mute" &
mute_pid=$!
cleanup() { kill "$mute_pid" 2>/dev/null; }
mkdir -p "$DOTS_DEV_DIR/mutepath"
printf '#!/bin/sh\nNIRI_SOCKET=%s exec %s "$@"\n' "$mute" "$DOTS_DEV_DIR/dots-pointer/dots-pointer" >"$DOTS_DEV_DIR/mutepath/dots-pointer"
chmod +x "$DOTS_DEV_DIR/mutepath/dots-pointer"
until_ok 2000 test -S "$mute"
out=$(PATH=$DOTS_DEV_DIR/mutepath:$PATH "$mouse" click $((fx + 300)) $((fy + 300)))
rc=$?
check "a pick with no answer in 500 ms exits 3 (got $rc: $out)" bash -c "[ $rc = 3 ] && jq -e '.refused == \"no answer\"' <<<'$out' >/dev/null"

# Over the factory: the click lands. Fullscreen puts its window-relative extents at logical pixels.
niri msg action toggle-window-floating --id "$factory"
niri msg action fullscreen-window --id "$factory"
focus "$factory"
# The first check box: "x y checked|-", or a button by name: "x y".
widget() {
  python3 - "$@" <<'EOF'
import sys, warnings
warnings.filterwarnings("ignore")
import gi
gi.require_version("Atspi", "2.0")
from gi.repository import Atspi
Atspi.init()
d = Atspi.get_desktop(0)
def walk(n):
    try:
        if (sys.argv[1] == "check" and n.get_role_name() == "check box") or (sys.argv[1] == "button" and n.get_role_name() == "button" and (n.get_name() or "").startswith(sys.argv[2])):
            return n
        for i in range(n.get_child_count()):
            hit = walk(n.get_child_at_index(i))
            if hit:
                return hit
    except Exception:
        return None
for i in range(d.get_child_count()):
    a = d.get_child_at_index(i)
    if a.get_name() == "gtk4-widget-factory":
        n = walk(a)
        if n:
            e = Atspi.Component.get_extents(n.get_component(), Atspi.CoordType.WINDOW)
            on = "checked" if n.get_state_set().contains(Atspi.StateType.CHECKED) else "-"
            print(e.x + e.width // 2, e.y + e.height // 2, on)
        break
EOF
}
fullscreen() { niri msg -j windows | jq -e ".[] | select(.id == $factory) | .layout.window_size == [$ow, $oh]" >/dev/null; }
until_ok 3000 fullscreen
has_check() { [ -n "$(widget check)" ]; }
until_ok 5000 has_check
read -r cx cy was < <(widget check)
"$mouse" click "$cx" "$cy"
rc=$?
flipped() { read -r _ _ now < <(widget check); [ "$now" != "$was" ]; }
check "mouse click over the factory's first check box exits 0 (got $rc)" test "$rc" = 0
check "and flips it from $was" until_ok 2000 flipped

# A dialog the factory opens on that click joins, and takes keys; 6 s on, only the click can make it join.
read -r bx by _ < <(widget button "Sans")
sleep 6
"$mouse" click "$bx" "$by"
dialog() { niri msg -j windows | jq -r '.[] | select(.title == "Pick a Font") | .id' | head -1; }
has_dialog() { [ -n "$(dialog)" ]; }
check "a click on the font button opens a dialog" until_ok 5000 has_dialog
dlg=$(dialog)
check "which is an agent window" bash -c "'$scripts/desk' window '$dlg' | jq -e .agent >/dev/null"
focus "$dlg"
wtype -k Shift_L
"$scripts/screen" type serif
rc=$?
check "and takes screen type (got $rc)" test "$rc" = 0
"$scripts/screen" key Escape >/dev/null

# gui click: a GTK window titled poke with one button, Press, which writes a file when pressed.
poke() {
  cat <<EOF
import sys, gi
gi.require_version("Gtk", "4.0")
from gi.repository import GLib, Gtk
GLib.set_prgname("poke")
def activate(app):
    w = Gtk.ApplicationWindow(application=app, title="poke")
    b = Gtk.Button(label="Press")
    b.connect("clicked", lambda _: open("$DOTS_DEV_DIR/poked", "a").write("poke\\n"))
    w.set_child(b)
    w.present()
app = Gtk.Application(application_id="org.dots.Poke")
app.connect("activate", activate)
app.run([])
EOF
}
poke >"$DOTS_DEV_DIR/poke.py"
sleep 6
niri msg action spawn -- python3 "$DOTS_DEV_DIR/poke.py"
until_ok 5000 has_window org.dots.Poke
"$scripts/gui" click poke Press >/dev/null
rc=$?
sleep 0.5
check "gui click in a poke window no agent opened exits 3 (got $rc)" test "$rc" = 3
check "and presses nothing" test ! -e "$DOTS_DEV_DIR/poked"
"$scripts/gui" click poke Press --any >/dev/null
check "while gui click --any presses it" until_ok 2000 test -e "$DOTS_DEV_DIR/poked"
niri msg action close-window --id "$(window_of org.dots.Poke)"
gone() { ! has_window org.dots.Poke; }
until_ok 3000 gone
rm -f "$DOTS_DEV_DIR/poked"
"$scripts/screen" launch python3 "$DOTS_DEV_DIR/poke.py" >/dev/null
until_ok 5000 has_window org.dots.Poke
poke_up() { "$scripts/gui" find poke Press >/dev/null 2>&1; }
until_ok 5000 poke_up
"$scripts/gui" click poke Press >/dev/null
rc=$?
check "gui click in a launched poke window exits 0 (got $rc)" test "$rc" = 0
check "and presses its button" until_ok 2000 test -e "$DOTS_DEV_DIR/poked"

exit $((fails > 0))
}
