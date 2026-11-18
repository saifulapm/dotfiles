#!/usr/bin/env bash
# The chat's keys against the fake pxy: Tab to the reply list, y copies the picked block and Y the whole reply, m switches the alias, Shift+Enter breaks a line, Ctrl+N starts over; a hostile reply draws cleaned and the shell keeps answering.
{
source "$(dirname "$0")/lib-chat.sh"
source "$(dirname "$0")/lib.sh"
cleanup() { chat_cleanup; }
pasted() { [ "$(wl-paste --no-newline 2>/dev/null)" = "$1" ]; }

until_ok 5000 island_is '.surface == null'
open_chat
say "write a fish loop"
until_ok 10000 chat_is '.streaming == false and .blocks == 3'
wtype -k Tab
check "Tab moves to the reply list, on the reply's last block ($(chat | jq -c '{focus, pick}'))" until_ok 2000 chat_is '.focus == "replies" and .pick == 3'
wtype k
check "k picks the code block" until_ok 2000 chat_is '.pick == 2'
wtype y
check "y puts the code block on the clipboard ($(wl-paste --no-newline 2>/dev/null | head -1))" until_ok 2000 pasted $'for f in *\n    echo $f\nend'
wtype -M shift -k y -m shift
check "Y puts the whole reply on the clipboard" until_ok 2000 pasted "$(printf 'Here is one:\n\n```fish\nfor f in *\n    echo $f\nend\n```\n\nRun it in a folder.')"
wtype m
check "m switches to the default alias ($(chat | jq -c .alias))" until_ok 2000 chat_is '.alias == "default"'
wtype -k Tab
check "Tab from the reply list opens the history page ($(chat | jq -c '{focus, page}'))" until_ok 2000 chat_is '.focus == "history" and .page == "history"'
wtype -k Tab
until_ok 2000 chat_is '.focus == "input" and .keyboard'
wtype -- "two"
wtype -M shift -k Return -m shift
wtype -- "lines"
check "Shift+Enter breaks the line and sends nothing ($(chat | jq -c .input))" until_ok 2000 chat_is '.input == "two\nlines" and .streaming == false'
wtype -k Return
check "the next request asks the default alias" until_ok 3000 sent '.[-1].model == "default"'
until_ok 10000 chat_is '.streaming == false'
wtype -M ctrl n -m ctrl
check "Ctrl+N starts a new conversation ($(chat | jq -c '{conversation, rows}'))" until_ok 2000 chat_is '.conversation == null and .rows == 0 and .title == ""'

say "hostile"
until_ok 3000 chat_is '.streaming'
# The shell is asked its status all through the 1 MiB reply, and the slowest answer counts.
slowest=0
deadline=$(($(now_ms) + 20000))
while chat_is '.streaming' && (($(now_ms) < deadline)); do
  t0=$(now_ms)
  shell_status >/dev/null
  t=$(($(now_ms) - t0))
  ((t > slowest)) && slowest=$t
  sleep 0.05
done
check "all through a 1 MiB reply the shell answers within 500 ms (slowest ${slowest} ms)" test "$slowest" -lt 500
check "the reply draws without ESC or U+202E ($(chat | jq -c '.drawn[0].html'))" chat_is '.drawn | length == 3 and (map(.html) | join("") | test("[\u001b‮]") | not)'
check "the 1 MiB line draws cut" chat_is '.drawn[1].html | length < 4100'
exit "$fails"
}
