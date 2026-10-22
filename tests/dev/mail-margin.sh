#!/usr/bin/env bash
# The margin shows the Imbox unread count kak-mail writes as MAIL n before the other words, and no item at 0.
{
source "$(dirname "$0")/lib.sh"

until_ok 5000 shell_status >/dev/null
margins() { timeout 0.5 qs ipc call margins state 2>/dev/null; }
file="$XDG_STATE_HOME/dots/mail-unread"

# kak-mail writes a temp file and renames it over the count, so each write here does the same.
write_count() { printf '%s\n' "$1" >"$file.tmp" && mv "$file.tmp" "$file"; }

# With no goal and no failing sync in the dev session, a mail item opens the drawn right margin.
reads() {
  margins | jq -e --argjson n "$1" '(.right.mail | type) == "number" and .right.mail == $n and
    if $n > 0 then (.right.text | startswith("mail \($n)  ")) and (.drawn.right | startswith("MAIL \($n) — "))
    else (.right.text | contains("mail") | not) and (.drawn.right | contains("MAIL") | not) end' >/dev/null 2>&1
}
shows() {
  until_ok 3000 reads "$1"
  echo "     margins: $(margins | jq -c '{mail: .right.mail, text: .right.text, drawn: .drawn.right}')"
  reads "$1"
}

write_count 0
check "a count of 0 reports mail 0 and draws no mail item" shows 0
write_count 1
check "a count of 1 renamed over the file draws MAIL 1 first" shows 1
write_count 4
check "a count of 4 renamed over the file draws MAIL 4 first" shows 4
write_count 99999999999999999999
check "a count past what an int holds draws no mail item, not a wrapped number" shows 0
write_count 4
write_count 0
check "a count back at 0 takes the mail item away" shows 0

exit $((fails > 0))
}
