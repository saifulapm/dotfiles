#!/usr/bin/env bash
# JEV's workspace guard, against a stub curl: with only an agent window on the active workspace, screen find --jev sends; with a foot that no launch opened beside it, tiled or floating, it exits 3 naming that foot and sends nothing; with --any it sends; once that foot is on another workspace it sends again.
{
source "$(dirname "$0")/lib.sh"

scripts=$repo/home/dot_claude/skills/desktop/scripts
screen=$scripts/screen
stub=$DOTS_DEV_DIR/jev-bin
sends=$DOTS_DEV_DIR/jev-sends
mkdir -p "$stub"
printf '#!/usr/bin/env bash\necho sk-or-v1-not-a-real-key\n' >"$stub/pass"
cat >"$stub/curl" <<STUB
#!/usr/bin/env bash
cat >/dev/null
echo send >>'$sends'
printf '%s\n200' '{"answers":{"target":{"type":"box","box":{"left":0.4,"right":0.6,"top":0.4,"bottom":0.6},"confidence":0.9},"on_screen":{"type":"noul","noul":0.9}}}'
STUB
chmod +x "$stub/pass" "$stub/curl"
export PATH=$stub:$PATH
: >"$sends"
count() { wc -l <"$sends"; }
foot_ids() { niri msg -j windows | jq -r "[.[] | select(.app_id == \"$1\") | .id] | .[]"; }

# Saiful's foot first, before any launch, so it is never an agent window.
niri msg action spawn -- foot -a saiful-foot -c /dev/null
until_ok 5000 bash -c "[ -n \"\$(niri msg -j windows | jq '.[] | select(.app_id == \"saiful-foot\")')\" ]"
his=$(foot_ids saiful-foot)
niri msg action move-window-to-workspace --window-id "$his" --focus false 2
"$screen" launch foot -a agent-jev -c /dev/null >/dev/null
ours=$("$screen" wait window-open --app agent-jev | jq -er .window.id)
niri msg action focus-window --id "$ours"
check "his foot ($his) is on workspace 2, ours ($ours) alone on the active one" bash -c "niri msg -j windows | jq -e '[.[] | select(.id == $his or .id == $ours) | .workspace_id] | .[0] != .[1]' >/dev/null"

out=$("$screen" find "the terminal" --jev)
rc=$?
check "with only our foot there, find --jev sends once and prints a point (rc $rc: $out)" bash -c "[ $rc = 0 ] && [ $(count) = 1 ] && jq -e '.x and .y' <<<'$out' >/dev/null"

niri msg action move-window-to-workspace --window-id "$his" --focus false "$(niri msg -j workspaces | jq '.[] | select(.is_active) | .idx')"
niri msg action focus-window --id "$ours"
out=$("$screen" find "the terminal" --jev)
rc=$?
check "with his foot beside ours, find --jev exits 3 naming his foot (rc $rc: $out)" bash -c "[ $rc = 3 ] && jq -e '.refused == \"not an agent window\" and .window.app_id == \"saiful-foot\"' <<<'$out' >/dev/null"
check "and sends nothing ($(count) sends)" test "$(count)" = 1
out=$("$screen" check "is a terminal open?" --jev)
check "check --jev refuses the same: $out" bash -c "jq -e '.refused == \"not an agent window\"' <<<'$out' >/dev/null && [ $(count) = 1 ]"

niri msg action toggle-window-floating --id "$his"
check "his foot floats now" bash -c "niri msg -j windows | jq -e '.[] | select(.id == $his) | .is_floating' >/dev/null"
out=$("$screen" find "the terminal" --jev)
check "floating, it still refuses: $out" bash -c "jq -e '.window.app_id == \"saiful-foot\"' <<<'$out' >/dev/null && [ $(count) = 1 ]"

out=$("$screen" find "the terminal" --jev --any)
rc=$?
check "with --any, find sends (rc $rc, $(count) sends)" bash -c "[ $rc = 0 ] && [ $(count) = 2 ]"
line=$(tail -1 "$XDG_STATE_HOME/dots/agent-journal.ndjson")
check "the refusal and the send are journal lines, the send with its answer: $(cut -c1-160 <<<"$line")" bash -c "jq -e '.outcome == \"ok\" and .jev.on_screen == 0.9' <<<'$line' >/dev/null && grep -c '\"refused\"' '$XDG_STATE_HOME/dots/agent-journal.ndjson' | grep -qx 3"

exit $((fails > 0))
}
