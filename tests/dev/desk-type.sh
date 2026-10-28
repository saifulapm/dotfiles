#!/usr/bin/env bash
# screen type reaches a newly launched widget factory's entry whole, its first key Shift_L: 60 characters read back in order five runs in five, and a newline in the text is dropped, never sent as Return. A new foot, and a foot an agent click opened, each read Return, x, Return sent right after a Return elsewhere; unprimed, the first Return arrives as Escape.
{
source "$(dirname "$0")/lib.sh"

dots_pointer_build || exit 1
scripts=$repo/home/dot_claude/skills/desktop/scripts
screen=$scripts/screen
# Every wtype the scripts run is logged, then run.
mkdir -p "$DOTS_DEV_DIR/wtype-log"
printf '#!/usr/bin/env bash\necho "$*" >>%q\nexec %q "$@"\n' "$DOTS_DEV_DIR/wtype.log" "$(command -v wtype)" >"$DOTS_DEV_DIR/wtype-log/wtype"
chmod +x "$DOTS_DEV_DIR/wtype-log/wtype"
PATH=$DOTS_DEV_DIR/wtype-log:$PATH
typed=$DOTS_DEV_DIR/typed
mkdir -p "$typed"
# A foot whose shell is a raw cat into a file, so every key that reaches it shows there.
raw() { echo "stty raw -echo; exec cat >$typed/$1"; }
read_is() { [ "$(cat "$typed/$1" 2>/dev/null)" = "$2" ]; }
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

check "nothing went through wtype before the factory's first screen type" test ! -s "$DOTS_DEV_DIR/wtype.log"
text=The_quick_brown_fox_jumps_over_the_lazy_dog_0123456789-AbCdE
check "the text is 60 characters" test "${#text}" = 60
for run in 1 2 3 4 5; do
  entry clear
  until_ok 2000 entry_is ""
  "$screen" type "$text"
  rc=$?
  first=$(head -2 "$DOTS_DEV_DIR/wtype.log" | tr '\n' '|')
  [ "$run" = 1 ] && check "the first key into the new factory is Shift_L, then the text (log: $first)" test "$first" = "-k Shift_L|-- T|"
  check "run $run: screen type of 60 characters exits 0 (got $rc)" test "$rc" = 0
  check "run $run: and the entry reads all 60 in order" until_ok 2000 entry_is "$text"
done

entry clear
until_ok 2000 entry_is ""
"$screen" type $'a\nb'
check "screen type \$'a\\nb' into the entry reads ab, the newline dropped" until_ok 2000 entry_is ab

# The keymap trap: niri sends a new window wtype's keymap only when it differs from the last one sent, so a Return into it right after a Return elsewhere arrives as Escape without the Shift_L first.
keys_land() {
  "$screen" key Return >/dev/null && "$screen" type x >/dev/null && "$screen" key Return >/dev/null
  until_ok 2000 read_is "$1" $'\rx\r'
}
"$screen" key Return >/dev/null
"$screen" launch foot -c /dev/null -a fresh sh -c "$(raw fresh)" >/dev/null
until_ok 5000 has_window fresh
check "a launched foot reads Return, x, Return from screen key Return, type x, key Return after a Return into the factory" keys_land fresh

# A foot that opens another on the first mouse report a click sends it: the new one is an agent window by that click, and one wtype has not typed into.
"$screen" launch foot -c /dev/null -a opener sh -c "stty raw -echo; printf '\033[?1000h'; head -c 1 >/dev/null; exec foot -c /dev/null -a dialog sh -c '$(raw dialog)'" >/dev/null
until_ok 5000 has_window opener
niri msg action fullscreen-window --id "$(window_of opener)"
read -r cx cy < <(niri msg -j focused-output | jq -r '.logical | "\(.x + .width / 2 | floor) \(.y + .height / 2 | floor)"')
sleep 0.5
"$scripts/mouse" click "$cx" "$cy"
until_ok 5000 has_window dialog
dialog=$(window_of dialog)
focus_is() { niri msg -j focused-window | jq -e ".id == $1" >/dev/null; }
# niri keeps focus on the fullscreen opener, where a real dialog's app would take it.
niri msg action focus-window --id "$dialog"
check "the foot the click opened takes focus" until_ok 3000 focus_is "$dialog"
check "and is an agent window" bash -c "'$scripts/desk' window $dialog | jq -e .agent >/dev/null"
check "and reads Return, x, Return the same way" keys_land dialog

exit $((fails > 0))
}
