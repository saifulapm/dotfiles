#!/usr/bin/env bash
# In the launcher, "? " and a question, then Enter, opens the chat with the question sent; an empty "? " does nothing on Enter.
{
source "$(dirname "$0")/lib-chat.sh"
source "$(dirname "$0")/lib.sh"
cleanup() { chat_cleanup; }

launcher() { timeout 0.5 qs ipc call launcher state 2>/dev/null; }
state_is() { launcher | jq -e "$@" >/dev/null 2>&1; }
open_launcher() { niri msg action spawn -- dots-call launcher toggle; until_ok 3000 state_is '.open and .query == "" and .keyboard and .settled'; }

until_ok 5000 island_is '.surface == null'
open_launcher
wtype -- "? "
check "'? ' shows the Ask chip ($(launcher | jq -c '{chip: .chip.name, query}'))" until_ok 2000 state_is '.chip.name == "Ask" and .query == "? "'
wtype -k Return
sleep 0.5
check "Enter on an empty '? ' leaves the launcher open ($(island | jq -c .surface))" island_is '.surface == "launcher"'
wtype -- "hello"
until_ok 2000 state_is '.query == "? hello"'
wtype -k Return
check "Enter on '? hello' opens the chat ($(island | jq -c .surface))" until_ok 3000 island_is '.surface == "chat"'
check "and sends hello to pxy ($(chat | jq -c '{streaming, rows}'))" until_ok 3000 sent '.[-1].messages[-1].content == "hello"'
check "the chat reads the reply streaming or done" chat_is '.open and .rows >= 1'
exit "$fails"
}
