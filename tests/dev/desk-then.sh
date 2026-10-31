#!/usr/bin/env bash
# --then: mouse to --then windows prints the window list; a click on the widget factory's Page 2 tab with --then windows prints the window list with the factory focused; screen type hello --then shot into page 2's text view prints "stable": true and a shot whose OCR reads hello; gui click --then tree prints the tree after the click; over page 1's spinners, which never stop, --then shot returns 2.0-2.3 s after the call with "stable": false and exit 0.
{
source "$(dirname "$0")/lib.sh"

dots_pointer_build || exit 1
screen=$repo/home/dot_claude/skills/desktop/scripts/screen
gui=$repo/home/dot_claude/skills/desktop/scripts/gui

"$screen" launch gtk4-widget-factory >/dev/null
factory=$("$screen" wait window-open --app org.gtk.WidgetFactory4 | jq .window.id)
until_ok 5000 bash -c "'$gui' find widget Lorem >/dev/null 2>&1"
niri msg action focus-window --id "$factory"

# A word's centre in shot pixels, read by OCR off the whole output at native size, the nth match in reading order.
word() {
  "$screen" shot >/dev/null
  read -r sw sh < <(file /tmp/desk/shot.png | sed -n 's/.*, \([0-9]*\) x \([0-9]*\),.*/\1 \2/p')
  "$screen" zoom 0 0 "$sw" "$sh" >/dev/null
  read -r zw _ < <(file /tmp/desk/zoom.png | sed -n 's/.*, \([0-9]*\) x \([0-9]*\),.*/\1 \2/p')
  tesseract /tmp/desk/zoom.png - tsv 2>/dev/null |
    awk -F'\t' -v w="$1" -v n="${2:-1}" -v k="$sw/$zw" 'BEGIN { split(k, r, "/"); f = r[1] / r[2] } $12 == w && ++m == n { print int(($7 + $9 / 2) * f), int(($8 + $10 / 2) * f), int($7 * f); exit }'
}

read -r p1x p1y _ < <(word Page 1)
read -r p2x p2y _ < <(word Page 2)
check "OCR finds the Page 1 and Page 2 tabs ($p1x,$p1y and $p2x,$p2y)" test -n "${p2y:-}"
out=$("$screen" click "$p2x" "$p2y" --then windows)
rc=$?
check "screen click on Page 2 --then windows exits 0 (got $rc)" test "$rc" = 0
check "printing the window list with the factory focused: $out" bash -c "jq -e '(.stable | type) == \"boolean\" and (.windows | map(select(.focused)) | .[0].id) == $factory' <<<'$out' >/dev/null"

read -r lx ly lleft < <(word Lorem)
check "page 2 shows its Lorem text view ($lx,$ly)" test -n "${ly:-}"
"$screen" click $((lleft - 2)) "$ly" >/dev/null
# The text cursor draws in the space after the last word typed, where OCR reads it as a letter, so a second word keeps it off hello; the toolbar's icons can read as text ahead of it on the same line.
out=$("$screen" type 'hello world ' --then shot)
rc=$?
check "screen type hello --then shot exits 0 (got $rc)" test "$rc" = 0
check "with a still screen and the shot's path: $out" bash -c "jq -e '.stable == true and .shot == \"/tmp/desk/shot.png\"' <<<'$out' >/dev/null"
# The shot itself, doubled: tesseract misses text as small as a 1280 px shot of this output draws it.
python3 -c 'import gi, sys; gi.require_version("GdkPixbuf", "2.0"); from gi.repository import GdkPixbuf as P; p = P.Pixbuf.new_from_file(sys.argv[1]); p.scale_simple(p.get_width() * 2, p.get_height() * 2, P.InterpType.BILINEAR).savev(sys.argv[2], "png", [], [])' /tmp/desk/shot.png "$DOTS_DEV_DIR/typed.png"
check "whose OCR reads hello" bash -c "tesseract '$DOTS_DEV_DIR/typed.png' - 2>/dev/null | grep -qE '(^| )hello world Lorem'"

# Page 1's two spinners and pulsing bar change every frame.
"$screen" click "$p1x" "$p1y" >/dev/null
sleep 0.5
t0=$(now_ms)
out=$("$screen" key Escape --then shot)
rc=$? took=$(($(now_ms) - t0))
check "over page 1's spinners, screen key --then shot exits 0 (got $rc)" test "$rc" = 0
check "saying the screen never stilled: $out" bash -c "jq -e '.stable == false and .shot == \"/tmp/desk/shot.png\"' <<<'$out' >/dev/null"
check "2.0-2.3 s after the call ($took ms)" test "$took" -ge 2000 -a "$took" -le 2300

out=$("$repo/home/dot_claude/skills/desktop/scripts/mouse" to 20 20 --then windows)
check "mouse to --then windows prints the window list too: $(cut -c1-80 <<<"$out")" bash -c "jq -e '(.stable | type) == \"boolean\" and (.windows | map(.id) | index($factory)) != null' <<<'$out' >/dev/null"

# A toggle button, by its ref since four share the name: GTK4's check boxes offer no action, and Page 2's Inform opens a dialog that takes the clicks after it.
"$gui" tree widget >"$DOTS_DEV_DIR/before.json"
had=$(jq '[.nodes[] | select(.role == "toggle button" and .name == "togglebutton")][0].states | index("pressed") != null' "$DOTS_DEV_DIR/before.json")
toggle=$(jq -r '[.nodes[] | select(.role == "toggle button" and .name == "togglebutton")][0].ref' "$DOTS_DEV_DIR/before.json")
out=$("$gui" click widget "$toggle" --then tree)
rc=$?
check "gui click on a toggle button --then tree exits 0 (got $rc)" test "$rc" = 0
pid=$(niri msg -j windows | jq ".[] | select(.id == $factory) | .pid")
i=$(jq '.widget.ref | split(":")[1] | tonumber' <<<"$out")
check "printing the click's result and the factory's tree: $(cut -c1-120 <<<"$out")" bash -c "jq -e '.ok == true and .action == \"click\" and (.stable | type) == \"boolean\" and .tree.pid == $pid' <<<'$out' >/dev/null"
# The tree is the one after the click: the toggle it pressed reads pressed there, and did not before.
check "where the toggle reads pressed, as it did not before ($had)" bash -c "[ '$had' = false ] && jq -e '.tree.nodes[] | select(.i == $i) | .states | index(\"pressed\") != null' <<<'$out' >/dev/null"

exit $((fails > 0))
}
