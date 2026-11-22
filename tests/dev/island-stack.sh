#!/usr/bin/env bash
# Notifications that pile up show as one stack with a count; Esc clears them all from the island at once, D only the one shown, and a mail notification opens its thread or the Imbox.
{
source "$(dirname "$0")/lib.sh"

island() { timeout 0.5 qs ipc call island state 2>/dev/null; }
island_is() { island | jq -e "$@" >/dev/null 2>&1; }
history() { timeout 0.5 qs ipc call notifs state 2>/dev/null | jq '[.summaries[] | select(startswith("Battery low"))] | length'; }
mod_i() { niri msg action spawn -- dots-call island focus; until_ok 2000 island_is '.focused'; sleep 0.3; }
opened=$DOTS_DEV_DIR/mail-opened

until_ok 3000 island_is '.mode == "rest"'
for n in 1 2 3; do
  notify-send -u critical -a Battery "Battery low $n" "1$n% left"
  until_ok 2000 island_is --arg s "Battery low $n" '.note.summary == $s'
done
check "three criticals from one app show as one stack of 3 ($(island | jq -c .stack))" island_is '.stack.count == 3 and .stack.app == "Battery" and .stack.same == 3 and .stack.others == 0'
check "the newest on top, its app line saying +2 more ($(island | jq -c '.note | {summary, app}'))" island_is '.note.summary == "Battery low 3" and (.note.app | test("\\+2 more$"))'
notify-send -u critical -a Mail "Mail from ann" ""
until_ok 2000 island_is '.note.summary == "Mail from ann"'
check "another app's notification joins the stack as one other app ($(island | jq -c .stack))" island_is '.stack.count == 4 and .stack.same == 1 and .stack.others == 1'
mod_i
wtype d
until_ok 2000 island_is '.stack.count == 3'
check "d puts away only the one shown ($(island | jq -c '{mode, stack}'))" island_is '.mode == "notification" and .stack.count == 3 and .note.summary == "Battery low 3"'
mod_i
wtype -k Escape
until_ok 3000 island_is '.mode == "rest"'
check "Esc clears the whole stack from the island at once" island_is '.mode == "rest" and .waiting == 0'
sleep 1
check "and nothing comes back" island_is '.mode == "rest"'
check "while the history keeps all three ($(history))" test "$(history)" = 3

thread=00000000000012ab
notify-send -t 0 -a Mail -h "string:x-dots-mail-thread:$thread" "1 new in your Imbox" "1 unread"
until_ok 2000 island_is '.note.summary == "1 new in your Imbox"'
mod_i
wtype -k Return
until_ok 3000 test -s "$opened"
check "Enter on one new mail opens its thread ($(cat "$opened" 2>/dev/null))" grep -qx "thread:$thread" "$opened"
rm -f "$opened"
notify-send -t 0 -a Mail -h "string:x-dots-mail-thread:x; touch $DOTS_DEV_DIR/pwned" "2 new in your Imbox" "2 unread"
until_ok 2000 island_is '.note.summary == "2 new in your Imbox"'
mod_i
wtype -k Return
until_ok 3000 test -s "$opened"
check "a notification naming no real thread opens the Imbox ($(cat "$opened" 2>/dev/null))" grep -qx Imbox "$opened"
check "and its hint ran nothing" test ! -e "$DOTS_DEV_DIR/pwned"
exit "$fails"
}
