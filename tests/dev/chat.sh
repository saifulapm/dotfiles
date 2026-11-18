#!/usr/bin/env bash
# Board 6's chat against the fake pxy: Mod+Shift+Space opens it on the chat alias, and a reply streams in as a paragraph, a code block and a paragraph.
{
source "$(dirname "$0")/lib-chat.sh"
source "$(dirname "$0")/lib.sh"
cleanup() { chat_cleanup; }

until_ok 5000 island_is '.surface == null'
open_chat
check "Mod+Shift+Space opens the chat in the island ($(island | jq -c .surface))" island_is '.surface == "chat"'
check "a new chat reads open, not streaming, on the chat alias ($(chat | jq -c '{open, streaming, alias}'))" chat_is '.open and .streaming == false and .alias == "chat"'
say "write a fish loop"
check "Enter sends it and the reply streams" until_ok 3000 chat_is '.streaming'
check "the reply ends ($(chat | jq -c '{streaming, blocks, error}'))" until_ok 10000 chat_is '.streaming == false'
check "it is three blocks: a paragraph, a code block, a paragraph ($(chat | jq .blocks))" chat_is '.blocks == 3'
check "the request asked the chat alias with the message ($(tail -1 "$requests" | jq -c '{model, stream}'))" jq -e '.model == "chat" and .stream == true and .messages[-1].content == "write a fish loop"' "$requests"
check "the header names the model pxy answered with ($(chat | jq -c .model))" chat_is '.model == "fake/chat-model"'
exit "$fails"
}
