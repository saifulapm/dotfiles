#!/usr/bin/env bash
# gui pick against a stub curl: without --jev it refuses and sends nothing; the request describes each widget as role, name and states, with a value only under --values and never a password's; 255 candidates print truncated and send nothing; the decision follows the confidence, destructive and present answers; pick never acts, and the journal holds what JEV answered.
{
source "$(dirname "$0")/lib.sh"

scripts=$repo/home/dot_claude/skills/desktop/scripts
gui=$scripts/gui
journal=$XDG_STATE_HOME/dots/agent-journal.ndjson
cleanup() {
  local id
  for id in $(niri msg -j windows | jq -r '.[] | select(.app_id | startswith("org.dots.Picker")) | .id'); do
    niri msg action close-window --id "$id" 2>/dev/null
  done
  return 0
}

# A curl that keeps the body it was sent and answers as answer.json says: the request's first widget or none, at the confidences given; a pass with a made-up key.
stub=$DOTS_DEV_DIR/stub-bin
mkdir -p "$stub"
cat >"$stub/curl" <<SH
#!/usr/bin/env bash
echo sent >>"$DOTS_DEV_DIR/curl.log"
prev=; for a in "\$@"; do [ "\$prev" = --data-binary ] && cp "\${a#@}" "$DOTS_DEV_DIR/curl.body"; prev=\$a; done
jq -c --slurpfile a "$DOTS_DEV_DIR/answer.json" '\$a[0] as \$a | {answers: {target: {type: "choice", choice: (if \$a.pick == "none" then "none" else (.questions.target.criteria | keys_unsorted[0]) end), confidence: \$a.confidence}, present: {type: "noul", noul: \$a.present}, destructive: {type: "noul", noul: \$a.destructive}}}' "$DOTS_DEV_DIR/curl.body"
printf '\n200'
SH
printf '#!/usr/bin/env bash\necho sk-or-v1-stub\n' >"$stub/pass"
chmod +x "$stub/curl" "$stub/pass"
export PATH=$stub:$PATH
answer() { jq -nc --arg p "$1" --argjson c "$2" --argjson d "$3" --argjson pr "${4:-0.95}" '{pick: $p, confidence: $c, destructive: $d, present: $pr}' >"$DOTS_DEV_DIR/answer.json"; }
sends() { wc -l <"$DOTS_DEV_DIR/curl.log" 2>/dev/null || echo 0; }

# "few": a button that notes its presses, a field holding text, a password field and an insensitive button; "many": 255 buttons.
cat >"$DOTS_DEV_DIR/picker.py" <<PY
import sys, gi
gi.require_version("Gtk", "4.0")
from gi.repository import GLib, Gtk
mode = sys.argv[1]
GLib.set_prgname("picker-" + mode)
def activate(app):
    w = Gtk.ApplicationWindow(application=app, title="picker-" + mode)
    box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
    if mode == "many":
        for n in range(255):
            box.append(Gtk.Button(label=f"b{n}"))
        s = Gtk.ScrolledWindow()
        s.set_child(box)
        w.set_child(s)
    else:
        go = Gtk.Button(label="Go")
        go.connect("clicked", lambda _: open("$DOTS_DEV_DIR/pressed", "a").write("x\n"))
        box.append(go)
        note = Gtk.Entry()
        note.update_property([Gtk.AccessibleProperty.LABEL], ["Note"])
        note.set_text("shopping list")
        box.append(note)
        secret = Gtk.PasswordEntry()
        secret.update_property([Gtk.AccessibleProperty.LABEL], ["Secret"])
        secret.set_text("hunter2-secret")
        box.append(secret)
        dead = Gtk.Button(label="Dead")
        dead.set_sensitive(False)
        box.append(dead)
        w.set_child(box)
    w.present()
app = Gtk.Application(application_id="org.dots.Picker." + mode)
app.connect("activate", activate)
app.run([])
PY

# many opens before the launch, so it is no agent window; a window opening within 5 s after one would be.
niri msg action spawn -- python3 "$DOTS_DEV_DIR/picker.py" many
until_ok 15000 bash -c "'$gui' find picker-many b254 >/dev/null 2>&1"
"$scripts/screen" launch python3 "$DOTS_DEV_DIR/picker.py" few >/dev/null
until_ok 8000 bash -c "'$gui' find picker-few Go >/dev/null 2>&1"
answer first 0.8 0.1

out=$("$gui" pick picker-few "the Go button")
rc=$?
check "gui pick without --jev exits 3 (got $rc)" test "$rc" = 3
check "printing jev not granted: $out" jq -e '. == {refused: "jev not granted"}' <<<"$out"
check "and sends nothing" test "$(sends)" = 0

out=$("$gui" pick picker-few "the Go button" --jev)
rc=$?
check "gui pick --jev exits 0 (got $rc)" test "$rc" = 0
check "sending one request" test "$(sends)" = 1
descs=$(jq -c '.questions.target.criteria | del(.none) | [.[] | fromjson]' "$DOTS_DEV_DIR/curl.body")
check "whose widgets are role, name and states only: $descs" jq -e 'length >= 3 and all(.[]; keys == ["name", "role", "states"])' <<<"$descs"
check "the insensitive button and the bare labels are no candidates" jq -e 'all(.[]; .name != "Dead" and .role != "label")' <<<"$descs"
check "printing the first widget's ref, act at 0.8: $out" jq -e '(.ref | test("^s[0-9a-f]{4}:[0-9]+$")) and .confidence == 0.8 and .destructive == 0.1 and .decision == "act"' <<<"$out"
check "the journal line holds the answer" jq -e '.tool == "gui" and .args[0] == "pick" and .jev.choice != null' <<<"$(tail -1 "$journal")"

"$gui" pick picker-few "the Note field" --jev --values >/dev/null
check "with --values the field's value goes, and never the password's: $(jq -c '.questions.target.criteria' "$DOTS_DEV_DIR/curl.body" | cut -c1-300)" jq -e '.questions.target.criteria | del(.none) | [.[] | fromjson] | (any(.[]; .value == "shopping list")) and all(.[]; .role != "password text" or (has("value") | not))' "$DOTS_DEV_DIR/curl.body"
check "and no request ever held the password" bash -c "! grep -q hunter2 '$DOTS_DEV_DIR/curl.body' '$journal'"

answer first 0.8 0.6
check "destructive at 0.6 and 0.8 sure is confirm" bash -c "'$gui' pick picker-few 'the Go button' --jev | jq -e '.decision == \"confirm\"' >/dev/null"
answer first 0.95 0.6
check "destructive and 0.95 sure is act" bash -c "'$gui' pick picker-few 'the Go button' --jev | jq -e '.decision == \"act\"' >/dev/null"
answer first 0.6 0.1
check "0.6 sure is confirm" bash -c "'$gui' pick picker-few 'the Go button' --jev | jq -e '.decision == \"confirm\"' >/dev/null"
answer first 0.5 0.1
check "0.5 sure is abstain" bash -c "'$gui' pick picker-few 'the Go button' --jev | jq -e '.decision == \"abstain\"' >/dev/null"
answer first 0.9 0.1 0.2
check "a present Noul of 0.2 is abstain" bash -c "'$gui' pick picker-few 'the Go button' --jev | jq -e '.decision == \"abstain\"' >/dev/null"
answer none 0.9 0.1
out=$("$gui" pick picker-few "a purple elephant" --jev)
check "none is abstain with no ref: $out" jq -e '.ref == null and .decision == "abstain"' <<<"$out"
check "and no pick pressed Go" test ! -e "$DOTS_DEV_DIR/pressed"

before=$(sends)
out=$("$gui" pick picker-many "button b7" --jev --any)
rc=$?
check "255 candidates exit 4 (got $rc)" test "$rc" = 4
check "printing truncated 255: $out" jq -e '. == {truncated: 255}' <<<"$out"
check "and send nothing" test "$(sends)" = "$before"

# One button's subtree is few enough to send, but its window is no agent window.
b7=$("$gui" tree picker-many | jq -r '.nodes[] | select(.name == "b7") | .ref')
out=$("$gui" pick picker-many "button b7" --jev --root "$b7")
rc=$?
check "gui pick --root $b7 in a window that is no agent window exits 3 (got $rc): $out" jq -e '.refused == "not an agent window"' <<<"$out"
check "and sends nothing" test "$(sends)" = "$before"

exit $((fails > 0))
}
