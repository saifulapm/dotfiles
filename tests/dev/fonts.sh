#!/usr/bin/env bash
# The nested shell's temp data dir still finds the fonts installed for the user.
source "$(dirname "$0")/lib.sh"

paper_up() { niri msg -j layers | jq -e 'any(.[]; .namespace == "dots-paper")' >/dev/null; }
until_ok 5000 paper_up
pid=$(systemctl --user show -p MainPID --value "$DOTS_DEV_UNIT")
data=$(tr '\0' '\n' <"/proc/$pid/environ" | sed -n 's/^XDG_DATA_HOME=//p')
family=$(XDG_DATA_HOME=$data fc-match -f '%{family[0]}' 'Maple Mono')
echo "     XDG_DATA_HOME=$data resolves Maple Mono to: $family"
check "the shell's data dir finds Maple Mono" test "$family" = "Maple Mono"

exit $((fails > 0))
