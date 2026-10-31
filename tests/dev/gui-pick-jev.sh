#!/usr/bin/env bash
# gui pick for real, through OpenRouter, so only with JEV_ALLOWED=1, which sends the nested widget factory's widget names and states and nothing else: "the check box labelled checkbutton" comes back as a ref to a check box named checkbutton, decision act, and the box's checked state is unchanged.
{
[ "${JEV_ALLOWED:-}" = 1 ] || { echo "skip gui-pick-jev.sh: it sends widget names to OpenRouter, so it runs only with JEV_ALLOWED=1"; exit 0; }
source "$(dirname "$0")/lib.sh"

scripts=$repo/home/dot_claude/skills/desktop/scripts
gui=$scripts/gui
cleanup() {
  local id
  for id in $(niri msg -j windows | jq -r '.[] | select(.app_id == "org.gtk.WidgetFactory4") | .id'); do
    niri msg action close-window --id "$id" 2>/dev/null
  done
  return 0
}
# The nested env points pass at an empty store; this check alone reads the real OpenRouter key, through the real pass.
mkdir -p "$DOTS_DEV_DIR/jev-bin"
printf '#!/usr/bin/env bash\nexec env -u PASSWORD_STORE_DIR -u GNUPGHOME %q "$@"\n' "$(command -v pass)" >"$DOTS_DEV_DIR/jev-bin/pass"
chmod +x "$DOTS_DEV_DIR/jev-bin/pass"
export PATH=$DOTS_DEV_DIR/jev-bin:$PATH

"$scripts/screen" launch gtk4-widget-factory >/dev/null
until_ok 15000 bash -c "'$gui' find gtk4-widget-factory Lorem >/dev/null 2>&1"
boxes() { "$gui" tree gtk4-widget-factory | jq -c '[.nodes[] | select(.role == "check box") | .states | index("checked") != null]'; }
before=$(boxes)

out=$("$gui" pick gtk4-widget-factory "the check box labelled checkbutton" --jev)
rc=$?
check "gui pick of the check box labelled checkbutton exits 0 (got $rc)" test "$rc" = 0
picked=$("$gui" get gtk4-widget-factory "$(jq -r .ref <<<"$out")" states 2>/dev/null)
check "printing a ref to a check box named checkbutton ($picked), decision act: $out" bash -c "jq -e '.decision == \"act\"' <<<'$out' >/dev/null && jq -e '.widget.role == \"check box\" and .widget.name == \"checkbutton\"' <<<'$picked' >/dev/null"
check "and every check box is as it was ($before)" test "$(boxes)" = "$before"

exit $((fails > 0))
}
