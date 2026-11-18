#!/usr/bin/env bash
# Esc mid-reply lets the reply finish behind the island's waiting dot, and opening the chat again shows the whole reply and puts the dot out.
{
source "$(dirname "$0")/lib-chat.sh"
source "$(dirname "$0")/lib.sh"
cleanup() { chat_cleanup; }

until_ok 5000 island_is '.surface == null'
open_chat
say "slow"
until_ok 3000 chat_is '.streaming'
wtype -k Escape
until_ok 2000 island_is '.surface == null'
check "Esc mid-reply closes the chat while the reply streams on ($(island | jq -c .surface), $(chat | jq -c .streaming))" chat_is '.open == false and .streaming'
check "the reply ends behind the closed chat ($(chat | jq -c '{streaming, blocks}'))" until_ok 10000 chat_is '.streaming == false'
check "the resting island waits on it as one, 204 px wide with the dot ($(island | jq -c '{mode, waiting, width, dot, animating}'))" until_ok 3000 island_is '.mode == "rest" and .waiting == 1 and .width == 204 and .dot != null'
check "the chat holds the reply as unseen ($(chat | jq -c .unseen))" chat_is '.unseen'
open_chat
check "opening the chat again shows the whole reply ($(chat | jq -c '{blocks, unseen}'))" chat_is '.blocks == 3 and .unseen == false'
check "and the island waits on nothing ($(island | jq -c .waiting))" island_is '.waiting == 0'
exit "$fails"
}
