#!/usr/bin/env bash
# The desktop skill's worked example, as SKILL.md spells it, opens foot, types echo hi and reads hi back by OCR; scripts/screen refuses input while locked, with exit 3.
{
source "$(dirname "$0")/lib.sh"

skill=$repo/home/dot_claude/skills/desktop
lock_is() { timeout 0.5 qs ipc call lock state 2>/dev/null | jq -e "$1" >/dev/null 2>&1; }
# The fenced block under "The worked example"; a nested foot reads /dev/null, since the live foot.ini themes every foot.
example=$(awk '/\*\*The worked example\*\*/ { on = 1; next } on && /^```sh$/ { inside = 1; next } inside && /^```$/ { exit } inside' "$skill/SKILL.md" | sed 's|spawn -- foot |spawn -- foot -c /dev/null |')
check "SKILL.md has the worked example, opening foot and reading it with tesseract" grep -q 'tesseract' <<<"$example"
foot_count() { niri msg -j windows | jq '[.[] | select(.app_id == "foot")] | length'; }

niri msg action spawn -- dots-call lock lock
until_ok 3000 lock_is '.locked and .secure'
"$skill/scripts/screen" type hi >/dev/null 2>&1
rc=$?
check "while locked, scripts/screen type hi refuses with exit code 3 (got $rc)" test "$rc" = 3
check "and nothing reached the password field" lock_is '.field == 0'

# An agent's way in: a lease, whose monitors go dark a second later; foot keeps drawing without frame callbacks, so the example needs no light.
timeout 0.5 qs ipc call lock unlock claude 5 >/dev/null
until_ok 3000 lock_is '.locked == false and .monitorsOff == 1'

out=$(bash -c "$example" 2>&1)
rc=$?
echo "     example printed: $(tr '\n' ' ' <<<"$out")"
check "the example reads hi back by OCR, and says so by its exit code" bash -c "[ $rc = 0 ] && grep -qxE '\\s*hi\\s*' <<<\"\$1\"" _ "$out"
check "and closes its foot" test "$(foot_count)" = 0

timeout 0.5 qs ipc call lock lock >/dev/null
until_ok 3000 lock_is '.locked and .secure'
wtype dots-test-pass
wtype -k Return
until_ok 3000 lock_is '.locked == false'

exit $((fails > 0))
}
