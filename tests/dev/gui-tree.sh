#!/usr/bin/env bash
# gui tree prints one JSON object of at most 1000 nodes and 32 KB and spills the whole tree to a 0700 directory; a second tree and any later gui call sweep old spills; a small tree has no spill; gui click reports whether the press worked.
{
source "$(dirname "$0")/lib.sh"

scripts=$repo/home/dot_claude/skills/desktop/scripts
gui=$scripts/gui
window_of() { niri msg -j windows | jq -r ".[] | select(.app_id == \"$1\") | .id" | sort -n | tail -1; }
has_window() { [ -n "$(window_of "$1")" ]; }
cleanup() {
  local id
  for id in $(niri msg -j windows | jq -r '.[] | select(.app_id | startswith("org.dots.Tree")) | .id'); do
    niri msg action close-window --id "$id" 2>/dev/null
  done
  return 0
}

# One GTK window per mode: "flood" has 1100 buttons, "poke" has a button that works and one that is insensitive.
cat >"$DOTS_DEV_DIR/tree.py" <<PY
import sys, gi
gi.require_version("Gtk", "4.0")
from gi.repository import GLib, Gtk
mode = sys.argv[1]
GLib.set_prgname(mode)
def activate(app):
    w = Gtk.ApplicationWindow(application=app, title=mode)
    if mode == "flood":
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        for n in range(1100):
            box.append(Gtk.Button(label=f"button number {n}"))
        s = Gtk.ScrolledWindow()
        s.set_child(box)
        w.set_child(s)
    else:
        box = Gtk.Box()
        ok = Gtk.Button(label="Press")
        ok.connect("clicked", lambda _: open("$DOTS_DEV_DIR/poked", "a").write("poke\n"))
        dead = Gtk.Button(label="Dead")
        dead.set_sensitive(False)
        box.append(ok)
        box.append(dead)
        w.set_child(box)
    w.present()
app = Gtk.Application(application_id="org.dots.Tree." + mode)
app.connect("activate", activate)
app.run([])
PY

spill_dir=$XDG_RUNTIME_DIR/desk/$(basename "$NIRI_SOCKET")
up() { "$gui" find "$1" "$2" >/dev/null 2>&1; }

niri msg action spawn -- python3 "$DOTS_DEV_DIR/tree.py" flood
until_ok 8000 has_window org.dots.Tree.flood
flood_up() { up flood "button number 1099"; }
until_ok 15000 flood_up

"$gui" tree flood >"$DOTS_DEV_DIR/tree1.json"
rc=$?
spill=$(jq -r '.spill // empty' "$DOTS_DEV_DIR/tree1.json")
check "gui tree of 1100 buttons exits 0 (got $rc) and names a spill" test "$rc" = 0 -a -n "$spill"
check "its inline nodes are at most 1000" jq -e '(.nodes | length) <= 1000 and (.nodes | length) > 0' "$DOTS_DEV_DIR/tree1.json"
check "and the output is at most 32768 bytes" test "$(wc -c <"$DOTS_DEV_DIR/tree1.json")" -le 32768
check "the spill's directory is mode 700" test "$(stat -c %a "$(dirname "$spill")")" = 700
check "and the file is mode 600" test "$(stat -c %a "$spill")" = 600
check "the spill holds every node, more than 1000, with no spill key" jq -e '(.nodes | length) > 1000 and (has("spill") | not) and .count == (.nodes | length)' "$spill"
check "and count is the spill's length" jq -e --slurpfile s "$spill" '.count == $s[0].count' "$DOTS_DEV_DIR/tree1.json"
check "the inline nodes are the spill's first nodes, index for index" jq -e --slurpfile s "$spill" '.nodes == $s[0].nodes[: (.nodes | length)]' "$DOTS_DEV_DIR/tree1.json"
check "and the first node is a button with a four-number box" jq -e '.nodes[0].role == "button" and .nodes[0].i >= 0 and (.nodes[0].box | length) == 4 and .app == "flood" and (.pid | type) == "number"' "$DOTS_DEV_DIR/tree1.json"

"$gui" tree flood >"$DOTS_DEV_DIR/tree2.json"
spill2=$(jq -r '.spill // empty' "$DOTS_DEV_DIR/tree2.json")
check "a second gui tree writes its own spill" test -n "$spill2" -a "$spill2" != "$spill" -a -e "$spill2"
check "and removes the first one" test ! -e "$spill"

old=$spill_dir/tree-1000.json
echo '{}' >"$old"
touch -d '61 min ago' "$old"
fresh=$spill_dir/tree-2000.json
echo '{}' >"$fresh"
touch -d '59 min ago' "$fresh"
"$gui" apps >/dev/null
check "a spill aged 61 min is gone after the next gui call" test ! -e "$old"
check "while one aged 59 min stays" test -e "$fresh"
rm -f "$fresh"

niri msg action spawn -- python3 "$DOTS_DEV_DIR/tree.py" poke
until_ok 8000 has_window org.dots.Tree.poke
poke_up() { up poke Press; }
until_ok 8000 poke_up
"$gui" tree poke >"$DOTS_DEV_DIR/tree3.json"
check "a small tree prints no spill" jq -e 'has("spill") | not' "$DOTS_DEV_DIR/tree3.json"
check "and its count equals its nodes' length" jq -e '.count == (.nodes | length) and .count == 2' "$DOTS_DEV_DIR/tree3.json"
check "and the spill of the tree before it is gone" test ! -e "$spill2"
check "gui tree --pid finds the same app" bash -c "'$gui' tree --pid $(jq .pid "$DOTS_DEV_DIR/tree3.json") | jq -e '.app == \"poke\" and .count == 2' >/dev/null"

out=$("$gui" click poke Dead --any)
rc=$?
check "gui click on an insensitive button exits 1 (got $rc)" test "$rc" = 1
check "printing ok false: $out" jq -e '.ok == false and .widget.name == "Dead"' <<<"$out"
check "and presses nothing" test ! -e "$DOTS_DEV_DIR/poked"
out=$("$gui" click poke Press --any)
rc=$?
check "gui click on a working button exits 0 (got $rc)" test "$rc" = 0
check "printing ok true: $out" jq -e '.ok == true and .widget.name == "Press" and (.action | type) == "string"' <<<"$out"
check "and presses it" until_ok 2000 test -e "$DOTS_DEV_DIR/poked"

exit $((fails > 0))
}
