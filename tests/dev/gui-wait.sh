#!/usr/bin/env bash
# gui wait --text returns within a second of an entry reading the text, and a wait for text that never comes exits 1 after its timeout with the last state; a timeout over 60 s is a usage error; --gone started right after the click that opens a popover returns only after the popover has shown and gone; --state returns once a toggle reads pressed.
{
source "$(dirname "$0")/lib.sh"

scripts=$repo/home/dot_claude/skills/desktop/scripts
gui=$scripts/gui
cleanup() {
  local id
  for id in $(niri msg -j windows | jq -r '.[] | select(.app_id == "org.dots.Waiter") | .id'); do
    niri msg action close-window --id "$id" 2>/dev/null
  done
  return 0
}

# Fill writes hello into Field 1 s after its click; Open shows a popover holding Item One 400 ms after its click and hides it 600 ms later; each notes the ms it did so.
cat >"$DOTS_DEV_DIR/waiter.py" <<PY
import time, gi
gi.require_version("Gtk", "4.0")
from gi.repository import GLib, Gtk
GLib.set_prgname("waiter")
def note(what):
    open("$DOTS_DEV_DIR/" + what, "w").write(str(int(time.time() * 1000)))
def activate(app):
    w = Gtk.ApplicationWindow(application=app, title="waiter")
    box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
    field = Gtk.Entry()
    field.update_property([Gtk.AccessibleProperty.LABEL], ["Field"])
    box.append(field)
    fill = Gtk.Button(label="Fill")
    fill.connect("clicked", lambda _: GLib.timeout_add(1000, lambda: (field.set_text("hello"), note("filled"), False)[-1]))
    box.append(fill)
    opener = Gtk.Button(label="Open")
    pop = Gtk.Popover()
    pop.set_autohide(False)
    pop.set_child(Gtk.Button(label="Item One"))
    pop.set_parent(opener)
    def show():
        pop.popup()
        note("shown")
        GLib.timeout_add(600, lambda: (pop.popdown(), note("hidden"), False)[-1])
        return False
    opener.connect("clicked", lambda _: GLib.timeout_add(400, show))
    box.append(opener)
    box.append(Gtk.ToggleButton(label="Flip"))
    w.set_child(box)
    w.present()
app = Gtk.Application(application_id="org.dots.Waiter")
app.connect("activate", activate)
app.run([])
PY

"$scripts/screen" launch python3 "$DOTS_DEV_DIR/waiter.py" >/dev/null
until_ok 8000 bash -c "'$gui' find waiter Flip >/dev/null 2>&1"

"$gui" click waiter Fill >/dev/null
out=$("$gui" wait waiter --text hello)
rc=$? done_ms=$(now_ms)
check "gui wait --text hello exits 0 (got $rc): $out" test "$rc" = 0
check "within 1 s of the entry reading hello ($((done_ms - $(cat "$DOTS_DEV_DIR/filled"))) ms)" test $((done_ms - $(cat "$DOTS_DEV_DIR/filled"))) -le 1000
check "naming the entry, never its text" jq -e '.widget.name == "Field" and (tostring | test("hello") | not)' <<<"$out"

t0=$(now_ms)
out=$("$gui" wait waiter --text nope --timeout 1)
rc=$? took=$(($(now_ms) - t0))
check "gui wait --text nope --timeout 1 exits 1 (got $rc)" test "$rc" = 1
check "after 1 to 1.5 s ($took ms)" test "$took" -ge 1000 -a "$took" -le 1500
check "printing the last state it saw: $out" jq -e '.ok == false and .timeout == 1 and .last.present == false' <<<"$out"
"$gui" wait waiter --text nope --timeout 61 >/dev/null 2>&1
check "--timeout 61 is a usage error (got $?)" test "$?" = 2

"$gui" click waiter Open >/dev/null
out=$("$gui" wait waiter --gone "Item One")
rc=$? done_ms=$(now_ms)
check "gui wait --gone right after the opener's click exits 0 (got $rc): $out" test "$rc" = 0
check "only after the popover showed" test "$done_ms" -gt "$(cat "$DOTS_DEV_DIR/shown")"
check "and after it went" test "$done_ms" -ge "$(cat "$DOTS_DEV_DIR/hidden")"
check "having seen it, not sat out the 2 s ($(jq .ms <<<"$out") ms)" jq -e '.ms < 2000' <<<"$out"

"$gui" click waiter Flip >/dev/null
out=$("$gui" wait waiter --state Flip pressed --timeout 3)
rc=$?
check "gui wait --state Flip pressed exits 0 (got $rc): $out" test "$rc" = 0
check "printing its states" jq -e '.widget.name == "Flip" and (.states | index("pressed"))' <<<"$out"

exit $((fails > 0))
}
