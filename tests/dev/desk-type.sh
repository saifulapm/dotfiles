#!/usr/bin/env bash
# screen type reaches a newly launched widget factory's entry whole: 60 characters read back in order five runs in five, and a newline in the text is dropped, never sent as Return.
{
source "$(dirname "$0")/lib.sh"

dots_pointer_build || exit 1
scripts=$repo/home/dot_claude/skills/desktop/scripts
screen=$scripts/screen
window_of() { niri msg -j windows | jq -r ".[] | select(.app_id == \"$1\") | .id" | sort -n | tail -1; }
has_window() { [ -n "$(window_of "$1")" ]; }

"$screen" launch gtk4-widget-factory >/dev/null
until_ok 8000 has_window org.gtk.WidgetFactory4
factory=$(window_of org.gtk.WidgetFactory4)
niri msg action fullscreen-window --id "$factory"
# The first entry's window-relative box, its text, or its text set to nothing, from AT-SPI.
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
        elif sys.argv[1] == "clear":
            Atspi.EditableText.set_text_contents(n.get_editable_text(), "")
        else:
            print(Atspi.Text.get_text(n.get_text(), 0, -1))
EOF
}
has_entry() { [ -n "$(entry box)" ]; }
until_ok 8000 has_entry
read -r ex ey < <(entry box)
"$scripts/mouse" click "$ex" "$ey"
entry_is() { [ "$(entry text)" = "$1" ]; }

text=The_quick_brown_fox_jumps_over_the_lazy_dog_0123456789-AbCdE
check "the text is 60 characters" test "${#text}" = 60
for run in 1 2 3 4 5; do
  entry clear
  until_ok 2000 entry_is ""
  "$screen" type "$text"
  rc=$?
  check "run $run: screen type of 60 characters exits 0 (got $rc)" test "$rc" = 0
  check "run $run: and the entry reads all 60 in order" until_ok 2000 entry_is "$text"
done

entry clear
until_ok 2000 entry_is ""
"$screen" type $'a\nb'
check "screen type \$'a\\nb' into the entry reads ab, the newline dropped" until_ok 2000 entry_is ab

exit $((fails > 0))
}
