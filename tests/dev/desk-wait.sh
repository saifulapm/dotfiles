#!/usr/bin/env bash
# screen wait on niri's events: a wait started before screen launch returns the widget factory's window within 5 s of the launch; with it open the same wait says already within 300 ms; a title wait returns when a foot's title comes to end in x; focus, workspace and overview waits return on their actions; a wait for nothing exits 1 after 10.0-10.5 s with the last state; --timeout 61 exits 2.
{
source "$(dirname "$0")/lib.sh"

screen=$repo/home/dot_claude/skills/desktop/scripts/screen
window_of() { niri msg -j windows | jq -r ".[] | select(.app_id == \"$1\") | .id" | sort -n | tail -1; }

# Started first; the factory launches a second later.
t0=$(now_ms)
"$screen" wait window-open --app org.gtk.WidgetFactory4 >"$DOTS_DEV_DIR/open.json" &
waiter=$!
sleep 1
launched=$(now_ms)
"$screen" launch gtk4-widget-factory >/dev/null
wait "$waiter"
rc=$? took=$(($(now_ms) - launched))
out=$(cat "$DOTS_DEV_DIR/open.json")
factory=$(window_of org.gtk.WidgetFactory4)
check "a wait started before screen launch exits 0 (got $rc)" test "$rc" = 0
check "returning the factory's window ($factory), not already: $out" bash -c "jq -e '.already == false and .window.id == $factory and .window.app_id == \"org.gtk.WidgetFactory4\"' <<<'$out' >/dev/null"
check "within 5 s of the launch ($took ms)" test "$took" -lt 5000

t0=$(now_ms)
out=$("$screen" wait window-open --app org.gtk.WidgetFactory4)
took=$(($(now_ms) - t0))
check "with it open, the same wait says already: $out" bash -c "jq -e '.already == true and .window.id == $factory' <<<'$out' >/dev/null"
check "within 300 ms ($took ms)" test "$took" -lt 300

# A foot whose shell sets its title by OSC 2, the second one once the check says go.
niri msg action spawn -- foot -c /dev/null -a titled sh -c "printf '\033]2;working\007'; until [ -e $DOTS_DEV_DIR/go ]; do sleep 0.1; done; printf '\033]2;all done x\007'; sleep 60"
titled_up() { [ "$(niri msg -j windows | jq -r '.[] | select(.app_id == "titled") | .title')" = working ]; }
until_ok 5000 titled_up
titled=$(window_of titled)
had=$(niri msg -j windows | jq -r ".[] | select(.id == $titled) | .title")
"$screen" wait title --id "$titled" --matches 'x$' >"$DOTS_DEV_DIR/title.json" &
waiter=$!
sleep 0.5
touch "$DOTS_DEV_DIR/go"
wait "$waiter"
out=$(cat "$DOTS_DEV_DIR/title.json")
check "a title wait on a foot titled '$had' returns when it ends in x: $out" bash -c "[ '$had' = working ] && jq -e '.already == false and .window.title == \"all done x\"' <<<'$out' >/dev/null"

"$screen" wait focus --id "$factory" >"$DOTS_DEV_DIR/focus.json" &
waiter=$!
sleep 0.5
niri msg action focus-window --id "$factory"
wait "$waiter"
check "a focus wait returns when the factory takes focus" jq -e ".window.id == $factory and .window.focused" "$DOTS_DEV_DIR/focus.json"

"$screen" wait workspace 2 >"$DOTS_DEV_DIR/ws.json" &
waiter=$!
sleep 0.5
niri msg action focus-workspace 2
wait "$waiter"
check "a workspace wait returns on focus-workspace 2" jq -e '.already == false and .workspace.idx == 2' "$DOTS_DEV_DIR/ws.json"
niri msg action focus-workspace 1

"$screen" wait overview open >"$DOTS_DEV_DIR/overview.json" &
waiter=$!
sleep 0.5
niri msg action open-overview
wait "$waiter"
check "an overview wait returns after open-overview" jq -e '.already == false and .overview == "open"' "$DOTS_DEV_DIR/overview.json"
niri msg action close-overview

"$screen" wait window-closed --id "$titled" >"$DOTS_DEV_DIR/closed.json" &
waiter=$!
sleep 0.5
niri msg action close-window --id "$titled"
wait "$waiter"
check "a window-closed wait returns when the foot closes" jq -e ".closed == $titled and .already == false" "$DOTS_DEV_DIR/closed.json"

t0=$(now_ms)
out=$("$screen" wait window-open --app no.such.app)
rc=$? took=$(($(now_ms) - t0))
check "a wait for nothing exits 1 (got $rc)" test "$rc" = 1
check "after 10.0-10.5 s ($took ms)" test "$took" -ge 10000 -a "$took" -le 10500
check "with the last state seen" bash -c "jq -e '.timeout == 10 and (.last.windows | map(.id) | index($factory)) != null' <<<'$out' >/dev/null"
"$screen" wait window-open --app x --timeout 61 2>/dev/null
check "--timeout 61 exits 2 (got $?)" test "$?" = 2

exit $((fails > 0))
}
