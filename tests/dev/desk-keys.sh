#!/usr/bin/env bash
# screen type and key go only into an agent window or a shell surface holding the keyboard: a foot of Saiful's gets nothing and the refusal names it, --any reaches it, a launched widget factory's entry and a launched footclient take the text, and a window opening 6 s after the last action does not; each action and refusal leaves a journal line without the text.
{
source "$(dirname "$0")/lib.sh"

dots_pointer_build || exit 1
scripts=$repo/home/dot_claude/skills/desktop/scripts
screen=$scripts/screen
typed=$DOTS_DEV_DIR/typed
mkdir -p "$typed"
# A foot whose shell is a raw cat into a file, so every key that reaches it shows there.
raw() { echo "stty raw -echo; exec cat >$typed/$1"; }
read_is() { [ "$(cat "$typed/$1" 2>/dev/null)" = "$2" ]; }
window_of() { niri msg -j windows | jq -r ".[] | select(.app_id == \"$1\") | .id" | sort -n | tail -1; }
has_window() { [ -n "$(window_of "$1")" ]; }
focus_is() { niri msg -j focused-window | jq -e ".id == $1" >/dev/null; }
focus() { niri msg action focus-window --id "$1" && until_ok 2000 focus_is "$1"; }

niri msg action spawn -- foot -c /dev/null -a his sh -c "$(raw his)"
until_ok 5000 has_window his
his=$(window_of his)
focus "$his"
# wtype's first keymap reaches only windows open when it is sent (lessons 2026-10-24).
wtype -k Shift_L

out=$("$screen" type x)
rc=$?
check "screen type x into Saiful's foot exits 3 (got $rc)" test "$rc" = 3
check "printing a refusal that names the foot: $out" bash -c "jq -e '.refused == \"not an agent window\" and .window.app_id == \"his\" and .window.id == $his' <<<'$out' >/dev/null"
sleep 0.3
check "and the foot reads nothing" read_is his ""
"$screen" key Return >/dev/null
check "screen key Return into it exits 3 too" test $? = 3
"$screen" type x --any
check "while --any lets screen type x reach it" until_ok 2000 read_is his x

# niri gives the keys to a fullscreen window ahead of a Top-layer surface holding them, so the Island focused over Saiful's fullscreen foot holds nothing.
niri msg action fullscreen-window --id "$his"
full() { niri msg -j windows | jq -e ".[] | select(.id == $his) | .layout.window_size == [$(niri msg -j outputs | jq -r '[.[] | .logical | .width, .height] | join(",")')]" >/dev/null; }
until_ok 3000 full
niri msg action spawn -- qs ipc call island focus
island_holds() { niri msg -j layers | jq -e 'any(.[]; .namespace == "dots-island" and .keyboard_interactivity == "Exclusive")' >/dev/null; }
until_ok 3000 island_holds
sleep 0.3
"$screen" type z >/dev/null
rc=$?
check "the Island focused over his fullscreen foot: screen type z exits 3 (got $rc)" test "$rc" = 3
sleep 0.3
check "and his foot reads only the x --any sent" read_is his x
niri msg action fullscreen-window --id "$his"
until_ok 3000 island_holds
wtype -k Escape
island_lets_go() { ! island_holds; }
until_ok 3000 island_lets_go

"$screen" launch gtk4-widget-factory >/dev/null
until_ok 8000 has_window org.gtk.WidgetFactory4
factory=$(window_of org.gtk.WidgetFactory4)
niri msg action fullscreen-window --id "$factory"
# The first entry's window-relative box, and its text, from AT-SPI.
entry() {
  python3 - "$1" <<'EOF'
import sys, warnings
warnings.filterwarnings("ignore")
import gi
gi.require_version("Atspi", "2.0")
from gi.repository import Atspi
Atspi.init()
d = Atspi.get_desktop(0)
def walk(n):
    if n.get_role_name() == "text":
        return n
    for i in range(n.get_child_count()):
        hit = walk(n.get_child_at_index(i))
        if hit:
            return hit
for i in range(d.get_child_count()):
    a = d.get_child_at_index(i)
    if a.get_name() == "gtk4-widget-factory":
        n = walk(a)
        if not n:
            break
        if sys.argv[1] == "box":
            e = Atspi.Component.get_extents(n.get_component(), Atspi.CoordType.WINDOW)
            print(e.x + e.width // 2, e.y + e.height // 2)
        else:
            print(Atspi.Text.get_text(n.get_text(), 0, -1))
EOF
}
has_entry() { [ -n "$(entry box)" ]; }
until_ok 8000 has_entry
read -r ex ey < <(entry box)
"$scripts/mouse" click "$ex" "$ey"
entry_is() { [ "$(entry text)" = "$1" ]; }
before=$(entry text)
wtype -k Shift_L
"$screen" type hello
rc=$?
check "screen type hello into the launched factory's first entry exits 0 (got $rc)" test "$rc" = 0
check "and the entry reads hello (it read '$before')" until_ok 2000 entry_is "${before}hello"

# footclient's window is the server's pid, and still joins by its launch.
niri msg action spawn -- foot -c /dev/null --server
sleep 6
"$screen" launch footclient -a ours sh -c "$(raw ours)" >/dev/null
until_ok 5000 has_window ours
ours=$(window_of ours)
focus "$ours"
wtype -k Shift_L
"$screen" type y
check "a launched footclient takes screen type" until_ok 2000 read_is ours y

# 6 s after the last launch or action, a window opens on its own.
sleep 6
niri msg action spawn -- foot -c /dev/null -a late sh -c "$(raw late)"
until_ok 5000 has_window late
late=$(window_of late)
focus "$late"
wtype -k Shift_L
"$screen" type x >/dev/null
rc=$?
check "screen type x into a window opening 6 s after the last action exits 3 (got $rc)" test "$rc" = 3
sleep 0.3
check "and it reads nothing" read_is late ""

# A shell surface holding the keyboard takes keys whatever window is focused.
niri msg action spawn -- qs ipc call launcher open
exclusive() { niri msg -j layers | jq -e 'any(.[]; .keyboard_interactivity == "Exclusive")' >/dev/null; }
until_ok 3000 exclusive
"$screen" type calc
rc=$?
check "screen type into the open launcher exits 0 though Saiful's window has focus (got $rc)" test "$rc" = 0
query_is() { timeout 0.5 qs ipc call launcher state | jq -e ".query == \"$1\"" >/dev/null; }
check "and the launcher's query reads calc" until_ok 2000 query_is calc
check "while the late foot behind it reads nothing" read_is late ""

# The journal: the nested session's own, under its XDG_STATE_HOME.
journal=$XDG_STATE_HOME/dots/agent-journal.ndjson
check "every action left a journal line in the nested state dir" test -s "$journal"
hello=$(jq -c "select(.args[0] == \"type\" and .args[1].len == 5 and .window.id == $factory)" "$journal" | tail -1)
check "the type of hello is a line with \"len\":5 and a 64-hex sha256: $hello" bash -c "jq -e '.outcome == \"ok\" and (.args[1].sha256 | test(\"^[0-9a-f]{64}\$\"))' <<<'$hello' >/dev/null"
check "and no hello anywhere in the file" bash -c "! grep -q hello '$journal'"
check "the refusal in Saiful's foot is a line with outcome refused and his window" bash -c "jq -e 'select(.outcome == \"refused\" and .window.id == $his)' '$journal' | grep -q ."
check "and the launch is one too" bash -c "jq -e 'select(.args == [\"launch\", \"gtk4-widget-factory\"])' '$journal' | grep -q ."

exit $((fails > 0))
}
