#!/usr/bin/env bash
# The facts gui's m66 changes branch on, measured once and printed as one "probe {...}" line each: niri's tile position for a visible GTK4 window, whether each widget factory's entry reads back a write, whether the shell on the a11y bus has named launcher and control trees and its idle RSS, and, with JEV_ALLOWED=1, one choice through desk's JEV client. It records nothing; the rulings are written from its lines.
{
[ "${DOTS_GUI_PROBE:-}" = 1 ] || { echo "skip gui-probe.sh: a one-off measure, run with DOTS_GUI_PROBE=1"; exit 0; }
export DOTS_DEV_A11Y=1
source "$(dirname "$0")/lib.sh"

scripts=$repo/home/dot_claude/skills/desktop/scripts
gui=$scripts/gui
probe() { echo "probe $1"; }
window_of() { niri msg -j windows | jq -r ".[] | select(.app_id == \"$1\") | .id" | sort -n | tail -1; }
has_window() { [ -n "$(window_of "$1")" ]; }
cleanup() {
  local id
  for id in $(niri msg -j windows | jq -r '.[] | select(.app_id | startswith("org.gtk.WidgetFactory")) | .id'); do
    niri msg action close-window --id "$id" 2>/dev/null
  done
  return 0
}

# The shell's RSS first, before any tree walk or surface adds to it: 60 s at rest on the a11y bus.
shell_pid=$(systemctl --user show -p MainPID --value "$DOTS_DEV_UNIT")
sleep 60
rss=$(awk '/^VmRSS/ {print int($2 / 1024)}' "/proc/$shell_pid/status")
probe "$(jq -nc --argjson pid "$shell_pid" --argjson mib "$rss" '{finding: "quickshell rss", pid: $pid, idle_rss_mib: $mib, after_s: 60}')"

apps=$("$gui" apps)
probe "$(jq -nc --arg apps "$apps" '{finding: "apps", apps: ($apps | split("\n"))}')"
# The shell's app on the bus is whatever name has its pid.
shell_app=$(python3 -c '
import sys, gi
gi.require_version("Atspi", "2.0")
from gi.repository import Atspi
d = Atspi.get_desktop(0)
for i in range(d.get_child_count()):
    a = d.get_child_at_index(i)
    if a and a.get_process_id() == int(sys.argv[1]):
        print(a.get_name())
' "$shell_pid")
named() { "$gui" tree --pid "$shell_pid" --all | jq -c '{count, named: ([.nodes[] | select(.name != "")] | length), sample: ([.nodes[] | select(.name != "") | "\(.role) \(.name)"] | .[:12])}'; }
for surface in launcher control; do
  if [ -n "$shell_app" ]; then
    before=$(named)
    qs ipc call "$surface" open >/dev/null
    sleep 1.5
    open=$(named)
    qs ipc call "$surface" close >/dev/null
    sleep 0.5
  else
    before=null open=null
  fi
  probe "$(jq -nc --arg s "$surface" --arg app "$shell_app" --argjson b "${before:-null}" --argjson o "${open:-null}" '{finding: "quickshell tree", surface: $s, app: $app, closed: $b, open: $o}')"
done

niri msg action spawn -- gtk4-widget-factory
until_ok 8000 has_window org.gtk.WidgetFactory4
until_ok 15000 bash -c "'$gui' find gtk4-widget Lorem >/dev/null 2>&1"
w4=$(window_of org.gtk.WidgetFactory4)
probe "$(niri msg -j windows | jq -c --argjson id "$w4" '.[] | select(.id == $id) | {finding: "tile position", app_id, is_floating, layout}')"

# A button's box in window and in screen coordinates, the two GTK4 boxes could come from.
extents() {
  python3 -c '
import sys, json, gi
gi.require_version("Atspi", "2.0")
from gi.repository import Atspi
Atspi.set_timeout(3000, 3000)
d = Atspi.get_desktop(0)
def walk(n, depth=0):
    if n is None or depth > 60:
        return None
    if n.get_role_name() in ("button", "push button") and n.get_name():
        return n
    for i in range(n.get_child_count()):
        hit = walk(n.get_child_at_index(i), depth + 1)
        if hit:
            return hit
for i in range(d.get_child_count()):
    a = d.get_child_at_index(i)
    if a and sys.argv[1] in (a.get_name() or ""):
        b = walk(a)
        c = b.get_component()
        box = lambda t: (lambda e: [e.x, e.y, e.width, e.height])(Atspi.Component.get_extents(c, t))
        print(json.dumps({"app": a.get_name(), "button": b.get_name(), "window": box(Atspi.CoordType.WINDOW), "screen": box(Atspi.CoordType.SCREEN)}))
        break
' "$1"
}
probe "$(jq -c '{finding: "gtk4 extents"} + .' <<<"$(extents gtk4-widget)")"

# The first entry with editable set and read-only clear: write probe, then read it back from 300 ms to 2 s.
readback() {
  python3 -c '
import sys, json, time, gi
gi.require_version("Atspi", "2.0")
from gi.repository import Atspi
Atspi.set_timeout(3000, 3000)
d = Atspi.get_desktop(0)
def states(n):
    return {s.value_nick for s in n.get_state_set().get_states()}
def walk(n, depth=0):
    if n is None or depth > 60:
        return None
    s = states(n)
    if n.get_role_name() in ("entry", "text") and "editable" in s and "read-only" not in s and "sensitive" in s and n.get_editable_text():
        return n
    for i in range(n.get_child_count()):
        hit = walk(n.get_child_at_index(i), depth + 1)
        if hit:
            return hit
for i in range(d.get_child_count()):
    a = d.get_child_at_index(i)
    if a and sys.argv[1] in (a.get_name() or ""):
        n = walk(a)
        before = Atspi.Text.get_text(n, 0, -1)
        ok = Atspi.EditableText.set_text_contents(n.get_editable_text(), "probe")
        t0, reads = time.monotonic(), []
        time.sleep(0.3)
        while time.monotonic() - t0 < 2:
            reads.append(Atspi.Text.get_text(n, 0, -1))
            if reads[-1] == "probe":
                break
            time.sleep(0.1)
        print(json.dumps({"app": a.get_name(), "role": n.get_role_name(), "name": n.get_name(), "before": before, "reply": bool(ok), "read": reads[-1], "reads_back": reads[-1] == "probe", "after_ms": int((time.monotonic() - t0) * 1000)}))
        break
' "$1"
}
probe "$(jq -c '{finding: "read-back"} + .' <<<"$(readback gtk4-widget)")"

niri msg action spawn -- gtk3-widget-factory
until_ok 8000 has_window org.gtk.WidgetFactory
until_ok 15000 bash -c "'$gui' find gtk3-widget Lorem >/dev/null 2>&1 || '$gui' find gtk3-widget entry >/dev/null 2>&1"
probe "$(jq -c '{finding: "read-back"} + .' <<<"$(readback gtk3-widget)")"
probe "$(jq -c '{finding: "gtk3 extents"} + .' <<<"$(extents gtk3-widget)")"

if [ "${JEV_ALLOWED:-}" != 1 ]; then
  probe '{"finding": "choice", "skipped": "JEV_ALLOWED is not 1"}'
  exit 0
fi
# The nested env points pass at an empty store; this step alone reads the real OpenRouter key, through the real pass.
mkdir -p "$DOTS_DEV_DIR/jev-bin"
printf '#!/usr/bin/env bash\nexec env -u PASSWORD_STORE_DIR -u GNUPGHOME %q "$@"\n' "$(command -v pass)" >"$DOTS_DEV_DIR/jev-bin/pass"
chmod +x "$DOTS_DEV_DIR/jev-bin/pass"
"$gui" tree gtk4-widget | jq '[.nodes[] | {key: "w\(.i)", value: "\(.role) \(.name | @json)\(if (.states | length) > 0 then " [" + (.states | join(",")) + "]" else "" end)"}] | from_entries' >"$DOTS_DEV_DIR/candidates.json"
out=$(PATH=$DOTS_DEV_DIR/jev-bin:$PATH "$scripts/desk" jev choice "the check box labelled checkbutton" "$DOTS_DEV_DIR/candidates.json")
rc=$?
picked=$(jq -r --arg c "$(jq -r .choice <<<"$out" 2>/dev/null)" '.[$c] // "none"' "$DOTS_DEV_DIR/candidates.json")
probe "$(jq -nc --argjson rc "$rc" --arg out "$out" --arg w "$picked" --argjson n "$(jq length "$DOTS_DEV_DIR/candidates.json")" '{finding: "choice", rc: $rc, answer: ($out | fromjson? // $out), widget: $w, candidates: $n}')"
exit 0
}
