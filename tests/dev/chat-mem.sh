#!/usr/bin/env bash
# Board 6's chat reads mem through its three read tools: each call runs the fake mem as one argv, draws a chip, and its cut result goes back to the fake pxy until it answers.
{
source "$(dirname "$0")/lib-chat.sh"
source "$(dirname "$0")/lib.sh"
source "$(dirname "$0")/pointer.bash"
cleanup() {
  pointer_stop
  chat_cleanup
}
click_at() { local at; at=$(shell_spot "$1") && point click $at; }

lines() { if [ -f "$1" ]; then wc -l <"$1"; else echo 0; fi; }
sent_since() { (($(lines "$requests") > $1)); }
# Sends one message and waits for its whole turn, tool rounds included, to end; mem_from and req_from mark where the turn's lines start.
turn() {
  mem_from=$(lines "$mem_log")
  req_from=$(lines "$requests")
  say "$1"
  until_ok 3000 sent_since "$req_from"
  until_ok 15000 chat_is '.streaming == false'
}
turn_mem() { tail -n +$((mem_from + 1)) "$mem_log" 2>/dev/null; }
turn_mem_is() { turn_mem | jq -se "$@" >/dev/null 2>&1; }
last_request_is() { tail -1 "$requests" | jq -e "$@" >/dev/null 2>&1; }

until_ok 5000 island_is '.surface == null'
open_chat

turn "what did we decide about the island's shape?"
check "the shape question runs one mem search ($(turn_mem | jq -sc .))" turn_mem_is '. == [["search","--scope","all","island shape"]]'
check "its chip reads mem_search island shape ($(chat | jq -c .tools))" chat_is '.tools | index([{name: "mem_search", arg: "island shape"}]) != null'
check "the reply draws and the turn ends ($(chat | jq -c '{streaming, blocks, error}'))" chat_is '.streaming == false and .blocks >= 1'
check "the second request ends with the tool's result" jq -se '.[1].messages[-1].role == "tool"' "$requests"

turn "show shape-1"
check "show shape-1 runs mem show SHAPE-1 ($(turn_mem | jq -sc .))" turn_mem_is '. == [["show","SHAPE-1"]]'
turn "read the wiki"
check "the wiki runs mem --project dotfiles wiki spec ($(turn_mem | jq -sc .))" turn_mem_is '. == [["--project","dotfiles","wiki","spec"]]'

turn "pwn"
check "a query with a semicolon reaches mem as one argument ($(turn_mem | jq -sc .))" turn_mem_is '. == [["search","--scope","all","x; touch PWNED"]]'
check "no shell ran the query's touch" test ! -e "$HOME/PWNED" -a ! -e "$PWD/PWNED" -a ! -e "$chat_fake/PWNED"

turn "big result"
check "a 20 KiB result goes back cut to 8 KiB ($(tail -1 "$requests" | jq '.messages[-1].content | utf8bytelength'))" last_request_is '.messages[-1].role == "tool" and (.messages[-1].content | utf8bytelength) <= 8192 and (.messages[-1].content | utf8bytelength) > 8000'

turn "eleven"
check "eleven calls in one round run ten ($(turn_mem | wc -l))" turn_mem_is 'length == 10'
check "the eleventh is not run ($(tail -1 "$requests" | jq -c '.messages[-1]'))" last_request_is '.messages[-1].tool_call_id == "call_11" and (.messages[-1].content | startswith("not run: "))'

check "mem never ran a write command" jq -se '[.[][]] | any(IN("decide","ask","answer","plan","roadmap","log","idea","finding","handoff","--stdin")) | not' "$mem_log"
check "every request carries the three tools, but the one after the turn's 10 calls are spent" jq -se 'all(.[]; (.tools | length) == 3 or .messages[-1].tool_call_id == "call_11")' "$requests"

# The default alias is offered the same tools.
wtype -k Tab
until_ok 2000 chat_is '.focus == "replies"'
wtype m
until_ok 2000 chat_is '.alias == "default"'
wtype -k Tab
wtype -k Tab
until_ok 2000 chat_is '.focus == "input" and .keyboard'
turn "what about the shape"
check "a request on the default alias carries the three tools too ($(tail -1 "$requests" | jq -c '{model, n: (.tools | length)}'))" sent 'any(.[]; .model == "default" and (.tools | length) == 3)'

# Stop while a mem call runs: the round leaves the conversation, and the late answer joins no later turn.
say "slow tool"
until_ok 3000 chat_is '.tools | any(.arg == "slowly")'
click_at chat-send
check "stop during a mem call ends the turn ($(chat | jq -c .streaming))" until_ok 2000 chat_is '.streaming == false'
n=$(wc -l <"$requests")
say "write a fish loop"
until_ok 10000 chat_is '.streaming == false and .blocks == 3'
sleep 3
check "the next message sends one request, with no unanswered tool call in it ($(tail -1 "$requests" | jq -c '[.messages[] | .role]'))" \
  eval '[ "$(wc -l <"$requests")" -eq $((n + 1)) ] && sent ".[-1].messages[-2:] | map(.content) == [\"slow tool\", \"write a fish loop\"]"'

# A request after a tool round that fails can be asked again.
say "tool fail"
check "a failure after the tool round shows pxy's line ($(chat | jq -c .error))" until_ok 5000 chat_is '.error == "fake pxy: failed after the tools"'
n=$(wc -l <"$requests")
click_at chat-retry
check "Retry asks pxy again with the tool's answer ($(tail -1 "$requests" | jq -c '.messages[-1].role'))" \
  until_ok 3000 eval '[ "$(wc -l <"$requests")" -gt "$n" ] && sent ".[-1].messages[-1].role == \"tool\""'
exit "$fails"
}
