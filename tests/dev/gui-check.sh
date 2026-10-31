#!/usr/bin/env bash
# gui check and uncheck leave a GTK3 check box as asked, the second of two saying it already was; gui tree --depth 3 on gtk4-widget-factory stops three levels down with children_count on each cut node, and --root walks only one node's subtree, its refs working.
{
source "$(dirname "$0")/lib.sh"

scripts=$repo/home/dot_claude/skills/desktop/scripts
gui=$scripts/gui
cleanup() {
  local id
  for id in $(niri msg -j windows | jq -r '.[] | select(.app_id == "org.gtk.WidgetFactory4" or .app_id == "org.gtk.WidgetFactory" or .title == "box3") | .id'); do
    niri msg action close-window --id "$id" 2>/dev/null
  done
  return 0
}

# GTK3, since GTK4's check boxes offer no action.
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
checked() { "$gui" get box3 Tick states | jq -e '.states | index("checked") != null' >/dev/null; }

out=$("$gui" check box3 Tick)
rc=$?
check "gui check on a clear box exits 0 (got $rc)" test "$rc" = 0
check "printing verified with no already: $out" jq -e '.delivery == "verified" and (has("already") | not) and .widget.role == "check box"' <<<"$out"
check "and the box is checked" checked
out=$("$gui" check box3 Tick)
rc=$?
check "a second gui check exits 0 (got $rc)" test "$rc" = 0
check "printing verified, already: $out" jq -e '.delivery == "verified" and .already == true' <<<"$out"
check "and the box stays checked" checked
out=$("$gui" uncheck box3 Tick)
rc=$?
check "gui uncheck exits 0 (got $rc): $out" test "$rc" = 0
unchecked() { ! checked; }
check "and leaves checked out of its states" unchecked
out=$("$gui" uncheck box3 Tick)
check "a second gui uncheck says already: $out" jq -e '.already == true' <<<"$out"
check "the journal holds the four, each with its delivery" bash -c "[ \$(jq -c 'select(.tool == \"gui\" and (.args[0] == \"check\" or .args[0] == \"uncheck\")) | .delivery' '$XDG_STATE_HOME/dots/agent-journal.ndjson' | grep -c verified) = 4 ]"

# gtk3-widget-factory's window has no name on the bus, though niri shows its title; screen launch opened it, so its boxes take checks.
"$scripts/screen" launch gtk3-widget-factory >/dev/null
until_ok 15000 bash -c "'$gui' tree gtk3-widget-factory | jq -e '[.nodes[] | select(.role == \"check box\")] | length > 0' >/dev/null 2>&1"
box=$("$gui" tree gtk3-widget-factory | jq -r '[.nodes[] | select(.role == "check box" and (.states | index("checked") | not) and (.states | index("sensitive")))][0].ref')
out=$("$gui" check gtk3-widget-factory "$box")
rc=$?
check "gui check on a clear box of the launched gtk3-widget-factory exits 0 (got $rc): $out" jq -e '.delivery == "verified" and (has("already") | not)' <<<"$out"
check "and that box reads checked" bash -c "'$gui' get gtk3-widget-factory '$box' states | jq -e '.states | index(\"checked\")' >/dev/null"

niri msg action spawn -- gtk4-widget-factory
until_ok 15000 bash -c "'$gui' find gtk4-widget-factory Lorem >/dev/null 2>&1"
"$gui" tree gtk4-widget-factory --all >"$DOTS_DEV_DIR/all.json"
"$gui" tree gtk4-widget-factory --depth 3 >"$DOTS_DEV_DIR/cut.json"
check "gui tree --depth 3 goes no deeper than 3" jq -e '(.nodes | length) > 0 and all(.nodes[]; .depth <= 3)' "$DOTS_DEV_DIR/cut.json"
check "every node at depth 3 is a cut node with children_count above 0: $(jq -c '[.nodes[] | select(.depth == 3) | {role, children_count}]' "$DOTS_DEV_DIR/cut.json")" jq -e '[.nodes[] | select(.depth == 3)] | length > 0 and all(.[]; .children_count > 0)' "$DOTS_DEV_DIR/cut.json"
check "and no shallower node has one" jq -e 'all(.nodes[] | select(.depth < 3); has("children_count") | not)' "$DOTS_DEV_DIR/cut.json"

root=$(jq -r '[.nodes[] | select(.depth == 3)][0]' "$DOTS_DEV_DIR/cut.json")
"$gui" tree gtk4-widget-factory --root "$(jq -r .ref <<<"$root")" --all >"$DOTS_DEV_DIR/branch.json"
check "gui tree --root <that ref> --all starts at that node: $(jq -c '.nodes[0] | {depth, role, name}' "$DOTS_DEV_DIR/branch.json")" jq -e --argjson r "$root" '.nodes[0].depth == $r.depth and .nodes[0].role == $r.role and .nodes[0].name == $r.name' "$DOTS_DEV_DIR/branch.json"
check "and holds only its subtree: $(jq '.count' "$DOTS_DEV_DIR/branch.json") of $(jq '.count' "$DOTS_DEV_DIR/all.json") nodes" jq -e --slurpfile a "$DOTS_DEV_DIR/all.json" '.count > 1 and .count < $a[0].count and all(.nodes[1:][]; .depth > 3)' "$DOTS_DEV_DIR/branch.json"
deep=$(jq -r '.nodes[-1].ref' "$DOTS_DEV_DIR/branch.json")
check "whose refs work: gui get $deep" bash -c "'$gui' get gtk4-widget-factory '$deep' states >/dev/null"

exit $((fails > 0))
}
