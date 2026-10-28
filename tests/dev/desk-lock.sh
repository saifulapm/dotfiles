#!/usr/bin/env bash
# Every input path refuses while the session is locked: mouse click leaves the lock's field empty, gui click and screen drag exit 3, and a lock that arrives while a click's hit-test runs gets no press.
{
source "$(dirname "$0")/lib.sh"

dots_pointer_build || exit 1
scripts=$repo/home/dot_claude/skills/desktop/scripts
lock_is() { timeout 0.5 qs ipc call lock state 2>/dev/null | jq -e "$1" >/dev/null 2>&1; }
unlock() {
  wtype dots-test-pass
  wtype -k Return
  until_ok 3000 lock_is '.locked == false'
}
read -r ow oh < <(niri msg -j outputs | jq -r '[.[] | .logical][0] | "\(.width) \(.height)"')

"$scripts/screen" launch gtk4-widget-factory >/dev/null
factory() { niri msg -j windows | jq -r '.[] | select(.app_id == "org.gtk.WidgetFactory4") | .id'; }
factory_up() { [ -n "$(factory)" ]; }
until_ok 8000 factory_up
id=$(factory)
niri msg action fullscreen-window --id "$id"
fullscreen() { niri msg -j windows | jq -e ".[] | select(.id == $id) | .layout.window_size == [$ow, $oh]" >/dev/null; }
until_ok 3000 fullscreen
# The first check box as "x y checked|-"; fullscreen makes its window-relative box logical pixels.
box() {
  python3 - <<'EOF'
import warnings
warnings.filterwarnings("ignore")
import gi
gi.require_version("Atspi", "2.0")
from gi.repository import Atspi
Atspi.init()
d = Atspi.get_desktop(0)
def walk(n):
    try:
        if n.get_role_name() == "check box":
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
            print(e.x + e.width // 2, e.y + e.height // 2, "checked" if n.get_state_set().contains(Atspi.StateType.CHECKED) else "-")
        break
EOF
}
has_box() { [ -n "$(box)" ]; }
until_ok 5000 has_box
read -r cx cy was < <(box)
"$scripts/screen" shot >/dev/null

niri msg action spawn -- dots-call lock lock
until_ok 3000 lock_is '.locked and .secure'
out=$("$scripts/mouse" click 10 10)
rc=$?
check "locked, mouse click 10 10 exits 3 with {\"refused\":\"locked\"} (got $rc: $out)" bash -c "[ $rc = 3 ] && jq -e '. == {refused: \"locked\"}' <<<'$out' >/dev/null"
check "and the lock's password field stays empty" lock_is '.field == 0'
out=$("$scripts/gui" click gtk4-widget-factory checkbutton)
rc=$?
check "locked, gui click exits 3 (got $rc: $out)" bash -c "[ $rc = 3 ] && jq -e '.refused == \"locked\"' <<<'$out' >/dev/null"
out=$("$scripts/screen" drag 100 100 200 100)
rc=$?
check "locked, screen drag exits 3 (got $rc: $out)" bash -c "[ $rc = 3 ] && jq -e '.refused == \"locked\"' <<<'$out' >/dev/null"
out=$("$scripts/screen" type x --any)
rc=$?
check "locked, screen type --any exits 3 (got $rc)" test "$rc" = 3
check "and the field is still empty" lock_is '.field == 0'
unlock
read -r _ _ now < <(box)
check "nothing reached the factory while locked: its check box still reads $was" test "$now" = "$was"

# A dots-pointer that locks the session as soon as its pick has answered: the lock lands between the hit-test and the press.
mkdir -p "$DOTS_DEV_DIR/lockpath"
cat >"$DOTS_DEV_DIR/lockpath/dots-pointer" <<EOF
#!/usr/bin/env bash
"$DOTS_DEV_DIR/dots-pointer/dots-pointer" "\$@" || exit
case " \$* " in *" pick "*) dots-call lock lock >/dev/null; for _ in \$(seq 60); do dots-call lock state | jq -e .locked >/dev/null && break; sleep 0.05; done ;; esac
EOF
chmod +x "$DOTS_DEV_DIR/lockpath/dots-pointer"
focus_up() { niri msg action focus-window --id "$id"; }
focus_up
out=$(PATH=$DOTS_DEV_DIR/lockpath:$PATH "$scripts/mouse" click "$cx" "$cy")
rc=$?
check "a lock arriving during the hit-test refuses the click with exit 3 (got $rc: $out)" bash -c "[ $rc = 3 ] && jq -e '.refused == \"locked\"' <<<'$out' >/dev/null"
check "with the session locked" lock_is '.locked'
check "and the lock's field empty" lock_is '.field == 0'
unlock
read -r _ _ now < <(box)
check "and the check box never pressed: still $was" test "$now" = "$was"
# The same click with no lock flips it, so the check above can fail.
focus_up
"$scripts/mouse" click "$cx" "$cy"
flipped() { read -r _ _ v < <(box); [ "$v" != "$was" ]; }
check "while the same click unlocked flips it" until_ok 2000 flipped

exit $((fails > 0))
}
