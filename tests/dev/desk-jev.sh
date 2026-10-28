#!/usr/bin/env bash
# JEV for real, through OpenRouter, so only with JEV_ALLOWED=1, which sends shots of the nested widget factory and nothing else: screen find "the text entry that says Click icon to change mode" --jev prints a point, and a click there then screen type hi leaves an entry reading hi; a purple elephant exits 4; screen check says yes to "does a text entry read hi?" and no to "is a file dialog open?"; the journal holds the sends with no image.
{
[ "${JEV_ALLOWED:-}" = 1 ] || { echo "skip desk-jev.sh: it sends shots to OpenRouter, so it runs only with JEV_ALLOWED=1"; exit 0; }
source "$(dirname "$0")/lib.sh"

dots_pointer_build || exit 1
scripts=$repo/home/dot_claude/skills/desktop/scripts
screen=$scripts/screen
gui=$scripts/gui
journal=$XDG_STATE_HOME/dots/agent-journal.ndjson
# The nested env points pass at an empty store; this check alone reads the real OpenRouter key, through the real pass.
mkdir -p "$DOTS_DEV_DIR/jev-bin"
printf '#!/usr/bin/env bash\nexec env -u PASSWORD_STORE_DIR -u GNUPGHOME %q "$@"\n' "$(command -v pass)" >"$DOTS_DEV_DIR/jev-bin/pass"
chmod +x "$DOTS_DEV_DIR/jev-bin/pass"
export PATH=$DOTS_DEV_DIR/jev-bin:$PATH

# The text of every entry of the factory, one per line, read through AT-SPI's Text interface.
entries() {
  python3 -c '
import gi
gi.require_version("Atspi", "2.0")
from gi.repository import Atspi
def walk(n, depth=0):
    if n is None or depth > 40:
        return
    if n.get_role_name() in ("text", "entry") and n.get_text_iface():
        print(Atspi.Text.get_text(n, 0, -1))
    for i in range(n.get_child_count()):
        walk(n.get_child_at_index(i), depth + 1)
d = Atspi.get_desktop(0)
for i in range(d.get_child_count()):
    a = d.get_child_at_index(i)
    if a and "widget" in (a.get_name() or "").lower():
        walk(a)
'
}
export -f entries

"$screen" launch gtk4-widget-factory >/dev/null
factory=$("$screen" wait window-open --app org.gtk.WidgetFactory4 | jq .window.id)
until_ok 5000 bash -c "'$gui' find widget Lorem >/dev/null 2>&1"
niri msg action focus-window --id "$factory"
# The combo entry starts focused with its text selected, where typing alone would land; Tab takes focus to its arrow button, so only the click puts the keys in an entry.
"$screen" key Tab >/dev/null
check "focus is on no entry before the click: $("$gui" tree widget | jq -c '[.nodes[] | select(.states | index("focused")) | .role]')" bash -c "'$gui' tree widget | jq -e '[.nodes[] | select(.states | index(\"focused\")) | .role] | length == 1 and (.[0] | test(\"text|entry\") | not)' >/dev/null"
had=$(entries | grep -cx hi)

# Page 1's first two rows are combo box entries, and JEV's Box for "the first text entry" spans both, its centre on the greyed second one, so the entry goes by its placeholder.
out=$("$screen" find "the text entry that says Click icon to change mode" --jev)
rc=$?
check "find the Click icon entry --jev prints a point with both confidences (rc $rc: $out)" bash -c "[ $rc = 0 ] && jq -e '(.x | type) == \"number\" and (.y | type) == \"number\" and .confidence > 0 and .on_screen >= 0.5' <<<'$out' >/dev/null"
x=$(jq -r .x <<<"$out") y=$(jq -r .y <<<"$out")
"$screen" click "$x" "$y" >/dev/null
"$screen" type hi >/dev/null
until_ok 2000 bash -c "entries | grep -qx hi" _
check "a click there and screen type hi leave an entry reading hi ($had before; entries now: $(entries | tr '\n' '|' | cut -c1-120))" test "$(entries | grep -cx hi)" = $((had + 1))

out=$("$screen" find "a purple elephant" --jev)
rc=$?
check "find a purple elephant exits 4 (rc $rc: $out)" bash -c "[ $rc = 4 ] && jq -e '.found == false and .on_screen < 0.5' <<<'$out' >/dev/null"

out=$("$screen" check "does a text entry read hi?" --jev)
rc=$?
check "check does a text entry read hi? says yes at 0.5 or more (rc $rc: $out)" bash -c "[ $rc = 0 ] && jq -e '.yes == true and .probability >= 0.5' <<<'$out' >/dev/null"
out=$("$screen" check "is a file dialog open?" --jev)
rc=$?
check "check is a file dialog open? says no (rc $rc: $out)" bash -c "[ $rc = 0 ] && jq -e '.yes == false and .probability < 0.5' <<<'$out' >/dev/null"

sends=$(jq -c 'select(.args[0] == "find" or .args[0] == "check") | {args, outcome, jev}' "$journal")
check "the journal holds the four sends with their answers: $(tr '\n' ' ' <<<"$sends" | cut -c1-300)" bash -c "[ \$(grep -c '\"jev\"' <<<'$sends') = 4 ]"
check "and no image ($(wc -c <"$journal") bytes)" bash -c "[ \$(wc -c <'$journal') -lt 20000 ] && ! grep -q data_base64 '$journal'"

exit $((fails > 0))
}
