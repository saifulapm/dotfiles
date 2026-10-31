#!/usr/bin/env bash
# gui type reports what a read of the field shows, never the AT-SPI reply: a write that reads back is verified, one the field puts back is not delivered and safe to retry, one into an app that stops is unverified within 4 s and not safe to retry, and a read-only entry is refused untouched; the typed text is in no output and no journal line, which records the delivery.
{
source "$(dirname "$0")/lib.sh"

scripts=$repo/home/dot_claude/skills/desktop/scripts
gui=$scripts/gui
journal=$XDG_STATE_HOME/dots/agent-journal.ndjson
window_of() { niri msg -j windows | jq -r ".[] | select(.app_id == \"$1\") | .id" | sort -n | tail -1; }
has_window() { [ -n "$(window_of "$1")" ]; }
cleanup() {
  [ -n "${fixture_pid:-}" ] && kill -CONT "$fixture_pid" 2>/dev/null
  local id
  for id in $(niri msg -j windows | jq -r '.[] | select(.app_id | startswith("org.dots.Delivery")) | .id'); do
    niri msg action close-window --id "$id" 2>/dev/null
  done
  return 0
}

# Each entry is named for gui by its accessible label: Name takes writes, Fixed is read-only, Stubborn puts "old" back after every change, Frozen stops its own process on a change, before GTK answers the write.
cat >"$DOTS_DEV_DIR/delivery.py" <<'PY'
import os, signal, gi
gi.require_version("Gtk", "4.0")
from gi.repository import GLib, Gtk
GLib.set_prgname("delivery")
def labelled(w, name):
    w.update_property([Gtk.AccessibleProperty.LABEL], [name])
    return w
def activate(app):
    win = Gtk.ApplicationWindow(application=app, title="delivery")
    box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
    box.append(labelled(Gtk.Entry(), "Name"))
    fixed = labelled(Gtk.Entry(), "Fixed")
    fixed.set_text("keep")
    fixed.set_editable(False)
    box.append(fixed)
    stubborn = labelled(Gtk.Entry(), "Stubborn")
    stubborn.set_text("old")
    stubborn.connect("changed", lambda e: e.get_text() != "old" and GLib.idle_add(lambda: e.set_text("old")))
    box.append(stubborn)
    frozen = labelled(Gtk.Entry(), "Frozen")
    frozen.connect("changed", lambda e: e.get_text() and os.kill(os.getpid(), signal.SIGSTOP))
    box.append(frozen)
    win.set_child(box)
    win.present()
app = Gtk.Application(application_id="org.dots.Delivery")
app.connect("activate", activate)
app.run([])
PY

# The text of the entry labelled $1, read straight from AT-SPI.
text_of() {
  python3 - "$1" <<'EOF' 2>/dev/null
import sys, gi
gi.require_version("Atspi", "2.0")
from gi.repository import Atspi
d = Atspi.get_desktop(0)
def walk(n):
    if n.get_name() == sys.argv[1] and n.get_role_name() == "text":
        return n
    for i in range(n.get_child_count()):
        hit = walk(n.get_child_at_index(i))
        if hit:
            return hit
for i in range(d.get_child_count()):
    a = d.get_child_at_index(i)
    if a.get_name() == "delivery":
        print(Atspi.Text.get_text(walk(a), 0, -1))
EOF
}

niri msg action spawn -- python3 "$DOTS_DEV_DIR/delivery.py"
until_ok 8000 has_window org.dots.Delivery
until_ok 15000 bash -c "'$gui' find delivery Frozen >/dev/null 2>&1"
fixture_pid=$(niri msg -j windows | jq -r '.[] | select(.app_id == "org.dots.Delivery") | .pid')

out=$("$gui" type delivery Name hello --any)
rc=$?
check "gui type into a plain entry exits 0 (got $rc)" test "$rc" = 0
check "printing verified, not safe to retry, matched: $out" jq -e '.ok == true and .delivery == "verified" and .retry_safe == false and .matched == true and .widget.name == "Name" and .widget.role == "text" and (has("cause") | not)' <<<"$out"
check "and the entry reads hello" test "$(text_of Name)" = hello
check "the output holds no hello" bash -c "! grep -q hello <<<'$out'"
line=$(tail -1 "$journal")
check "the journal line records the delivery: $line" jq -e '.tool == "gui" and .outcome == "ok" and .delivery == "verified"' <<<"$line"
check "and holds no hello" bash -c "! grep -q hello '$journal'"

out=$("$gui" type delivery Fixed hello --any)
rc=$?
check "gui type into a read-only entry exits 3 (got $rc)" test "$rc" = 3
check "printing not editable: $out" jq -e '.refused == "not editable"' <<<"$out"
check "and the entry still reads keep" test "$(text_of Fixed)" = keep

out=$("$gui" type delivery Stubborn hello --any)
rc=$?
check "gui type into an entry that puts its text back exits 1 (got $rc)" test "$rc" = 1
check "printing not delivered, write_ignored, safe to retry: $out" jq -e '.ok == false and .delivery == "not_delivered" and .cause == "write_ignored" and .retry_safe == true and .matched == false' <<<"$out"
check "and the journal line says not_delivered" jq -e '.delivery == "not_delivered"' <<<"$(tail -1 "$journal")"

t0=$(now_ms)
out=$("$gui" type delivery Frozen hello --any 2>"$DOTS_DEV_DIR/frozen.err")
rc=$? ms=$(($(now_ms) - t0))
check "gui type into an app that stops on the write exits 0 (got $rc: $(tail -3 "$DOTS_DEV_DIR/frozen.err"))" test "$rc" = 0
check "printing unverified, timeout, not safe to retry: $out" jq -e '.delivery == "unverified" and .cause == "timeout" and .retry_safe == false' <<<"$out"
check "within 4 s (took $ms ms)" test "$ms" -lt 4000
check "and the fixture is stopped" bash -c "grep -q '^State:.*T' /proc/$fixture_pid/status"
kill -CONT "$fixture_pid"
frozen_is_hello() { [ "$(text_of Frozen)" = hello ]; }
check "once it resumes, the write has landed" until_ok 3000 frozen_is_hello
check "no journal line holds hello" bash -c "! grep -q hello '$journal'"

exit $((fails > 0))
}
