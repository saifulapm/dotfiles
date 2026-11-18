#!/usr/bin/env bash
# A pxy failure keeps the message and shows pxy's own line with Retry under it, and r asks again; the stop button ends a stalled reply and keeps what came.
{
source "$(dirname "$0")/lib-chat.sh"
source "$(dirname "$0")/lib.sh"
source "$(dirname "$0")/pointer.bash"
cleanup() {
  pointer_stop
  chat_cleanup
}
click_at() { local at; at=$(shell_spot "$1") && point click $at; }

until_ok 5000 island_is '.surface == null'
open_chat
pxy_stop
say "write a fish loop"
check "with pxy down the message stays and the chat names the refusal ($(chat | jq -c '{error, rows}'))" until_ok 3000 chat_is '.streaming == false and .rows == 1 and (.error | test("did not answer"))'
check "one line under it draws pxy's line with a red alert and Retry ($(chat | jq -c .failure))" chat_is '.failure.drawn and .failure.retry and .failure.alert == .danger'
pxy_start
wtype -k Tab
until_ok 2000 chat_is '.focus == "replies"'
wtype r
check "with pxy back, r asks again and the reply streams ($(chat | jq -c '{error, blocks}'))" until_ok 10000 chat_is '.streaming == false and .error == "" and .blocks == 3'
check "the retry sent the same message once more" sent '[.[] | .messages[-1].content] == ["write a fish loop"]'

wtype -k Tab
until_ok 2000 chat_is '.focus == "history"'
wtype -k Tab
until_ok 2000 chat_is '.focus == "input" and .keyboard'
say "send 401"
check "an HTTP 401 shows pxy's own message ($(chat | jq -c .error))" until_ok 3000 chat_is '.error == "fake pxy: invalid API key" and .failure.drawn'
click_at chat-retry
check "a click on Retry asks again" until_ok 3000 sent '[.[] | .messages[-1].content] | map(select(. == "send 401")) | length == 2'
say "stream error"
check "an error object in the stream shows pxy's own message ($(chat | jq -c .error))" until_ok 5000 chat_is '.streaming == false and .error == "fake pxy: upstream overloaded"'

say "stall"
until_ok 3000 chat_is '.streaming and .blocks == 1'
click_at chat-send
check "the stop button ends a stalled reply ($(chat | jq -c '{streaming, blocks}'))" until_ok 2000 chat_is '.streaming == false'
check "and the partial reply stays" chat_is '.drawn[0].html == "Thinking about it"'
exit "$fails"
}
