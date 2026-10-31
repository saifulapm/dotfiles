#!/usr/bin/env bash
# gui click judges a GTK3 check box by its checked state, finds no action on a GTK4 one and leaves its label alone, and a plain button stays unverified; gui get reads one property and withholds a password field's text; with three windows of one launched app, the two that open after the launch's 5 s are no agent windows, so a click in the one with its own title is refused, and so is one in the window that shares the agent window's title.
{
source "$(dirname "$0")/lib.sh"

scripts=$repo/home/dot_claude/skills/desktop/scripts
gui=$scripts/gui
window_count() { niri msg -j windows | jq "[.[] | select(.app_id == \"org.dots.Click\")] | length"; }
cleanup() {
  local id
  for id in $(niri msg -j windows | jq -r '.[] | select(.app_id == "org.dots.Click" or .title == "box3") | .id'); do
    niri msg action close-window --id "$id" 2>/dev/null
  done
  return 0
}

# Window "first" has a check box, a button that counts its presses, and a password field holding a secret; 6 s later the app opens "second" and another "first", each with its own button.
cat >"$DOTS_DEV_DIR/click.py" <<PY
import gi
gi.require_version("Gtk", "4.0")
from gi.repository import GLib, Gtk
GLib.set_prgname("click")
def later(app, title, label):
    w = Gtk.ApplicationWindow(application=app, title=title)
    b = Gtk.Button(label=label)
    b.connect("clicked", lambda _: open("$DOTS_DEV_DIR/pressed-" + label, "a").write("x\n"))
    w.set_child(b)
    w.present()
def activate(app):
    w = Gtk.ApplicationWindow(application=app, title="first")
    box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
    box.append(Gtk.CheckButton(label="Tick"))
    plain = Gtk.Button(label="Plain")
    plain.connect("clicked", lambda _: open("$DOTS_DEV_DIR/pressed-Plain", "a").write("x\n"))
    box.append(plain)
    secret = Gtk.PasswordEntry()
    secret.update_property([Gtk.AccessibleProperty.LABEL], ["Secret"])
    secret.set_text("hunter2-secret")
    box.append(secret)
    w.set_child(box)
    w.present()
    GLib.timeout_add(6000, lambda: (later(app, "second", "Two"), later(app, "first", "Three"), False)[-1])
app = Gtk.Application(application_id="org.dots.Click")
app.connect("activate", activate)
app.run([])
PY

# GTK3's check box offers a click; GTK4's offers no action at all.
cat >"$DOTS_DEV_DIR/box3.py" <<'PY'
import gi
gi.require_version("Gtk", "3.0")
from gi.repository import GLib, Gtk
GLib.set_prgname("box3")
w = Gtk.Window(title="box3")
w.add(Gtk.CheckButton(label="Tick"))
w.show_all()
Gtk.main()
PY

"$scripts/screen" launch python3 "$DOTS_DEV_DIR/box3.py" >/dev/null
until_ok 8000 bash -c "'$gui' find box3 Tick >/dev/null 2>&1"
out=$("$gui" click box3 Tick)
rc=$?
check "gui click on an unchecked GTK3 check box exits 0 (got $rc)" test "$rc" = 0
check "printing verified: $out" jq -e '.ok == true and .delivery == "verified" and .retry_safe == false and .widget.name == "Tick" and .widget.role == "check box"' <<<"$out"
check "and the box is checked" bash -c "'$gui' get box3 Tick states | jq -e '.states | index(\"checked\")' >/dev/null"

"$scripts/screen" launch python3 "$DOTS_DEV_DIR/click.py" >/dev/null
until_ok 8000 bash -c "'$gui' find click Tick >/dev/null 2>&1"
# The box's label is a node named Tick too, so the target names the role.
"$gui" click click "Tick check box" >"$DOTS_DEV_DIR/out" 2>"$DOTS_DEV_DIR/err"
rc=$?
check "gui click on a GTK4 check box exits 4 (got $rc: $(cat "$DOTS_DEV_DIR/out" "$DOTS_DEV_DIR/err"))" test "$rc" = 4
check "and its box stays unchecked" bash -c "'$gui' get click 'Tick check box' states | jq -e '.states | index(\"checked\") | not' >/dev/null"

out=$("$gui" click click Plain)
rc=$?
check "gui click on a plain button exits 0 (got $rc)" test "$rc" = 0
check "printing unverified: $out" jq -e '.ok == true and .delivery == "unverified" and .retry_safe == false and (has("cause") | not)' <<<"$out"
pressed_once() { [ "$(cat "$DOTS_DEV_DIR/pressed-Plain" 2>/dev/null)" = x ]; }
check "and presses it once" until_ok 2000 pressed_once

out=$("$gui" get click Secret text)
rc=$?
check "gui get on the password field's text exits 0 (got $rc)" test "$rc" = 0
check "printing text null, withheld: $out" jq -e '.text == null and .withheld == true and .widget.role == "password text"' <<<"$out"
out=$("$gui" get click Secret)
check "with no property it still withholds the text: $out" jq -e '.text == null and .withheld == true and (.states | type) == "array" and has("box")' <<<"$out"
check "the secret is in no output" bash -c "! grep -q hunter2 <<<'$out'"
out=$("$gui" get click Plain box)
check "gui get box prints the box alone, with its reason when null: $out" jq -e '(keys - ["widget", "box_reason"]) == ["box"]' <<<"$out"

until_ok 10000 test "$(window_count)" = 3
until_ok 5000 bash -c "'$gui' find click Three >/dev/null 2>&1"
out=$("$gui" click click Two)
rc=$?
check "gui click in the app's later window exits 3 (got $rc)" test "$rc" = 3
check "printing not an agent window, naming that window: $out" jq -e '.refused == "not an agent window" and .window.title == "second"' <<<"$out"
out=$("$gui" click click Three)
rc=$?
check "gui click in a later window titled like the agent window exits 3 (got $rc)" test "$rc" = 3
check "printing its refusal: $out" jq -e '.refused | type == "string"' <<<"$out"
check "neither button was pressed" test ! -e "$DOTS_DEV_DIR/pressed-Two" -a ! -e "$DOTS_DEV_DIR/pressed-Three"
out=$("$gui" click click Plain)
rc=$?
check "while a click in the agent window itself is refused too, its title being shared (got $rc)" test "$rc" = 3

exit $((fails > 0))
}
