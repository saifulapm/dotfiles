#!/usr/bin/env bash
# gui tree gives every node of gtk4-widget-factory a ref, unnamed buttons included, and gui click and type act on one; a ref from before a page switch answers stale and acts on nothing; a text two widgets match answers ambiguous with at most 10 refs and acts on nothing; snapshots are 0600 and go after an hour.
{
source "$(dirname "$0")/lib.sh"

scripts=$repo/home/dot_claude/skills/desktop/scripts
gui=$scripts/gui
snaps=$XDG_RUNTIME_DIR/desk/$(basename "$NIRI_SOCKET")
cleanup() {
  local id
  for id in $(niri msg -j windows | jq -r '.[] | select(.app_id == "org.gtk.WidgetFactory4") | .id'); do
    niri msg action close-window --id "$id" 2>/dev/null
  done
  return 0
}

"$scripts/screen" launch gtk4-widget-factory >/dev/null
until_ok 15000 bash -c "'$gui' find gtk4-widget-factory Lorem >/dev/null 2>&1"

"$gui" tree gtk4-widget-factory >"$DOTS_DEV_DIR/tree.json"
check "gui tree prints more than 50 nodes" jq -e '(.nodes | length) > 50' "$DOTS_DEV_DIR/tree.json"
check "each with a ref s<4 hex>:<its i>" jq -e 'all(.nodes[]; (.ref | test("^s[0-9a-f]{4}:[0-9]+$")) and (.ref | split(":")[1] | tonumber) == .i)' "$DOTS_DEV_DIR/tree.json"
check "unnamed buttons included" jq -e '[.nodes[] | select((.role | test("button")) and .name == "")] | length > 0' "$DOTS_DEV_DIR/tree.json"
snap=$snaps/snap-$(jq -r '.nodes[0].ref | .[1:5]' "$DOTS_DEV_DIR/tree.json").json
check "its snapshot is mode 600" test "$(stat -c %a "$snap")" = 600

# Page 1's linked pair of icon toggles has no names; the first is the one not pressed, so its click opens nothing and changes its state.
unnamed=$(jq -r '[.nodes[] | select(.role == "toggle button" and .name == "" and .depth == 10 and .i > 100)][0].ref' "$DOTS_DEV_DIR/tree.json")
out=$("$gui" click gtk4-widget-factory "$unnamed")
rc=$?
check "gui click on an unnamed button's ref $unnamed exits 0 (got $rc)" test "$rc" = 0
check "printing ok and the ref: $out" jq -e --arg r "$unnamed" '.ok == true and .widget.ref == $r and .widget.name == ""' <<<"$out"

entry=$(jq -r '[.nodes[] | select(.role == "text")][0].ref' "$DOTS_DEV_DIR/tree.json")
out=$("$gui" type gtk4-widget-factory "$entry" hello)
rc=$?
check "gui type hello into an entry's ref exits 0 (got $rc)" test "$rc" = 0
check "printing verified and not safe to retry: $out" jq -e --arg r "$entry" '.delivery == "verified" and .retry_safe == false and .widget.ref == $r' <<<"$out"

pressed() { "$gui" get gtk4-widget-factory "$1" states | jq -c '[.states[] | select(. == "pressed" or . == "checked")]'; }
toggles=$(jq -c '[.nodes[] | select(.role == "toggle button" and .name == "togglebutton") | .ref]' "$DOTS_DEV_DIR/tree.json")
before=$(for r in $(jq -r '.[]' <<<"$toggles"); do pressed "$r"; done | tr -d '\n')
out=$("$gui" click gtk4-widget-factory togglebutton)
rc=$?
check "gui click on a text four toggle buttons match exits 4 (got $rc)" test "$rc" = 4
check "printing them as ambiguous, at most 10, each with a ref, role and name: $(cut -c1-200 <<<"$out")" jq -e '(.ambiguous | length) >= 2 and (.ambiguous | length) <= 10 and all(.ambiguous[]; (.ref | test("^s[0-9a-f]{4}:[0-9]+$")) and .role == "toggle button" and .name == "togglebutton")' <<<"$out"
after=$(for r in $(jq -r '.[]' <<<"$toggles"); do pressed "$r"; done | tr -d '\n')
check "and none of them changed ($before, now $after)" test "$before" = "$after"
check "an ambiguous ref works: $(jq -r '.ambiguous[0].ref' <<<"$out")" bash -c "'$gui' get gtk4-widget-factory '$(jq -r '.ambiguous[0].ref' <<<"$out")' states >/dev/null"
"$gui" click gtk4-widget-factory "" >/dev/null 2>&1
check "an empty text is a usage error (got $?)" test "$?" = 2

old=$(jq -r '[.nodes[] | select(.role == "toggle button" and .name == "togglebutton")][0].ref' "$DOTS_DEV_DIR/tree.json")
was=$(pressed "$old")
out=$("$gui" click gtk4-widget-factory "Page _2 page tab")
check "the page tab for Page 2 takes the click: $out" jq -e '.ok == true' <<<"$out"
gone() { ! "$gui" find gtk4-widget-factory Lorem >/dev/null 2>&1; }
until_ok 3000 gone
out=$("$gui" click gtk4-widget-factory "$old")
rc=$?
check "page 1's toggle ref after the switch exits 4 (got $rc)" test "$rc" = 4
check "printing a named stale cause: $out" jq -e '.stale | IN("path_gone", "role_changed", "name_changed")' <<<"$out"
"$gui" click gtk4-widget-factory "Page _1 page tab" >/dev/null
until_ok 3000 bash -c "'$gui' find gtk4-widget-factory Lorem >/dev/null 2>&1"
now=$("$gui" tree gtk4-widget-factory | jq -r '[.nodes[] | select(.role == "toggle button" and .name == "togglebutton")][0].ref')
check "and back on page 1 that toggle is as it was ($was)" test "$(pressed "$now")" = "$was"

missing=$("$gui" get gtk4-widget-factory s0000:5 2>&1)
check "a ref whose snapshot is gone answers snapshot_gone, exit 4: $missing" bash -c "'$gui' get gtk4-widget-factory s0000:5 >/dev/null 2>&1; [ \$? = 4 ] && jq -e '.stale == \"snapshot_gone\"' <<<'$missing' >/dev/null"

aged=$snaps/snap-aaaa.json
echo '{}' >"$aged"
touch -d '61 min ago' "$aged"
young=$snaps/snap-bbbb.json
echo '{}' >"$young"
touch -d '59 min ago' "$young"
"$gui" apps >/dev/null
check "a snapshot aged 61 min is gone after the next gui call" test ! -e "$aged"
check "while one aged 59 min stays" test -e "$young"
check "and a second tree left the first snapshot alone" test -e "$snap"
rm -f "$young"

exit $((fails > 0))
}
