#!/usr/bin/env bash
# The chat keeps each conversation as one JSON file named by its start time, keeps the last 50, skips a file that is not JSON, and lists them on a history page that Tab reaches twice from a fresh chat and Enter reopens.
{
source "$(dirname "$0")/lib-chat.sh"
source "$(dirname "$0")/lib.sh"
cleanup() { chat_cleanup; }
store=$XDG_DATA_HOME/dots/chat
saved() { ls "$store" 2>/dev/null | grep -c '\.json$'; }
saved_is() { [ "$(saved)" = "$1" ]; }
file_is() { jq -e "${@:2}" "$1" >/dev/null 2>&1; }

until_ok 5000 island_is '.surface == null'
open_chat
say "write a fish loop"
until_ok 10000 chat_is '.streaming == false and .blocks == 3'
start=$(chat | jq .conversation)
# The name is the start time in ISO form with ':' and '.' made '-', so names sort by time.
name=$(date -u -d "@$((start / 1000))" +%Y-%m-%dT%H-%M-%S)-$(printf %03d $((start % 1000)))Z.json
check "the exchange is saved as one file named by its start ($(ls "$store" 2>/dev/null | tr '\n' ' '))" until_ok 3000 test -f "$store/$name"
check "it is the only file" saved_is 1
check "the file holds the messages, the alias and the model ($(jq -c '{start, alias, model, roles: [.messages[].role]}' "$store/$name" 2>/dev/null))" \
  file_is "$store/$name" --argjson s "$start" '.start == $s and .alias == "chat" and .model == "fake/chat-model" and ([.messages[].role] == ["user", "assistant"]) and .messages[0].content == "write a fish loop" and (.messages[1].content | startswith("Here is one:"))'

# 49 older conversations make 50, the first of them the oldest.
for i in $(seq 0 48); do
  s=$((1577836800000 + i * 60000))
  printf '{"start":%s,"title":"old %s","alias":"chat","model":"fake/chat-model","messages":[{"role":"user","content":"old question %s"}]}' "$s" "$i" "$i" >"$store/$(date -u -d "@$((s / 1000))" +%Y-%m-%dT%H-%M-%S)-000Z.json"
done
oldest=$store/2020-01-01T00-00-00-000Z.json
check "50 files are there before the 51st conversation" saved_is 50
wtype -M ctrl n -m ctrl
until_ok 2000 chat_is '.conversation == null and .rows == 0'
say "show me a fish loop again"
until_ok 10000 chat_is '.streaming == false and .blocks == 3'
check "the 51st conversation deletes the oldest file" until_ok 3000 test ! -e "$oldest"
check "leaving 50 ($(saved))" saved_is 50
check "the first exchange is still kept" test -f "$store/$name"

printf 'not json {' >"$store/2026-01-01T00-00-00-000Z.json"

systemctl --user restart "$DOTS_DEV_UNIT"
until_ok 10000 shell_status >/dev/null
until_ok 6000 at_rest
open_chat
check "the restarted shell opens a fresh chat ($(chat | jq -c '{rows, conversation}'))" chat_is '.rows == 0 and .conversation == null and .page == "chat"'
wtype -k Tab
check "Tab goes to the reply list, though there is no reply ($(chat | jq -c '{focus, pick}'))" until_ok 2000 chat_is '.focus == "replies"'
wtype -k Tab
check "Tab again opens the history page ($(chat | jq -c '{page, focus, n: (.history | length)}'))" until_ok 3000 chat_is '.page == "history" and .focus == "history" and (.history | length) == 50'
check "the file that is not JSON is skipped and the list draws" chat_is '.history | length == 50'
check "the last conversation is first, with its title, first question and age ($(chat | jq -c '.history[0]'))" \
  chat_is '.history[0] == {title: "show me a fish loop again", question: "show me a fish loop again", age: "now"}'
check "the first exchange is second" chat_is '.history[1].title == "write a fish loop"'
wtype j
wtype -k Return
check "Enter reopens the picked conversation ($(chat | jq -c '{page, focus, rows, title, conversation}'))" \
  until_ok 3000 chat_is --argjson s "$start" '.page == "chat" and .focus == "input" and .rows > 0 and .title == "write a fish loop" and .conversation == $s and .history == []'
check "with its messages: the question and the reply's three blocks" chat_is '.rows == 4'
say "and in bash"
until_ok 10000 chat_is '.streaming == false'
check "a reopened conversation sends its old messages, text only ($(tail -1 "$requests" | jq -c '[.messages[] | .role]'))" \
  sent '.[-1].messages | map(.role) == ["user", "assistant", "user"] and .[0].content == "write a fish loop"'
check "and saves back to its own file ($(jq -c '[.messages[].role]' "$store/$name" 2>/dev/null))" \
  until_ok 3000 file_is "$store/$name" '.messages | length == 4'
exit "$fails"
}
