#!/usr/bin/env bash
# screen doctor on the nested desktop, unlocked with every tool there, prints no blockers and exits 0 with the lock, the niri socket, the outputs, AT-SPI and each tool; locked it names the lock and dots-call lock unlock; with dots-pointer off PATH it names dots-pointer; with no a11y bus it names at-spi.
{
source "$(dirname "$0")/lib.sh"

dots_pointer_build || exit 1
screen=$repo/home/dot_claude/skills/desktop/scripts/screen
lock_is() { timeout 0.5 qs ipc call lock state 2>/dev/null | jq -e "$1" >/dev/null 2>&1; }
name=$(niri msg -j focused-output | jq -r .name)

out=$("$screen" doctor)
rc=$?
check "screen doctor on the unlocked nested desktop exits 0 (got $rc)" test "$rc" = 0
check "with no blockers and no next step: $out" bash -c "jq -e '.blockers == [] and .next == null' <<<'$out' >/dev/null"
check "naming the lock state, the niri socket and the focused output $name" bash -c "jq -e '.locked == false and .niri == {socket: \"$NIRI_SOCKET\", ok: true} and (.outputs | map(select(.focused)) | .[0].name) == \"$name\"' <<<'$out' >/dev/null"
check "and AT-SPI and every tool present" bash -c "jq -e '.at_spi == true and (.tools | keys) == [\"dots-pointer\", \"grim\", \"tesseract\", \"wtype\", \"ydotoold\"] and .tools.\"dots-pointer\" and .tools.grim and .tools.wtype' <<<'$out' >/dev/null"

# dots-pointer off PATH: every entry holding it goes, this check's build and ~/.local/bin alike.
bare=$(tr : '\n' <<<"$PATH" | while read -r d; do [ -x "$d/dots-pointer" ] || echo "$d"; done | paste -sd:)
out=$(PATH=$bare "$screen" doctor)
check "with dots-pointer off PATH, blockers name it: $out" bash -c "jq -e '.blockers == [\"dots-pointer\"] and .tools.\"dots-pointer\" == false' <<<'$out' >/dev/null"

# An a11y bus that is gone, as when a probe of the launcher replaced the live one.
out=$(AT_SPI_BUS_ADDRESS=unix:path=$DOTS_DEV_DIR/no-bus "$screen" doctor)
check "with no a11y bus, blockers name at-spi: $out" bash -c "jq -e '.at_spi == false and .blockers == [\"at-spi\"]' <<<'$out' >/dev/null"

niri msg action spawn -- dots-call lock lock
until_ok 3000 lock_is '.locked == true'
out=$("$screen" doctor)
rc=$?
check "locked, screen doctor exits 1 (got $rc)" test "$rc" = 1
check "with blockers holding locked and next naming dots-call lock unlock: $out" bash -c "jq -e '.locked == true and .blockers == [\"locked\"] and (.next | test(\"dots-call lock unlock\"))' <<<'$out' >/dev/null"

exit $((fails > 0))
}
