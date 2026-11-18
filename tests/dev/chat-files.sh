#!/usr/bin/env bash
# The chat takes files from the island's picker and images from the clipboard: chips above the field, text files fenced into the message, an image turn on the vision model only, and a file over its limit refused with one line.
{
source "$(dirname "$0")/lib-chat.sh"
source "$(dirname "$0")/lib.sh"
source "$(dirname "$0")/pointer.bash"
files=$(mktemp -d)
cleanup() {
  pointer_stop
  chat_cleanup
  rm -rf "$files"
}
click_at() { local at; at=$(shell_spot "$1") && point click $at; }
pk_state() { timeout 0.5 dots-call picker state 2>/dev/null; }
pk_is() { pk_state | jq -e "$@" >/dev/null 2>&1; }
lines() { if [ -f "$requests" ]; then wc -l <"$requests"; else echo 0; fi; }
# Ctrl+O opens the picker over the chat; Ctrl+L types the folder, whose one file Enter picks, and the chat has the keyboard back after.
attach() {
  wtype -M ctrl o -m ctrl
  until_ok 4000 pk_is '.open and .settled and .keyboard and .listed'
  wtype -M ctrl l -m ctrl
  until_ok 2000 pk_is '.pathMode'
  wtype "$1/" -k Return
  until_ok 3000 pk_is --arg f "$1" '.folder == $f and .listed'
  wtype -k Return
  until_ok 3000 pk_is '.open == false'
  until_ok 3000 chat_is '.keyboard and .settled'
}

mkdir -p "$files/one" "$files/two" "$files/three"
{ printf 'MARKER-NOTES\n'; head -c 2035 /dev/zero | tr '\0' 'n'; } >"$files/one/notes.txt"
head -c $((600 * 1024)) /dev/zero | tr '\0' 'a' >"$files/two/big.txt"
head -c $((6 * 1024 * 1024)) /dev/zero >"$files/three/big.png"
grim -g "0,0 8x8" "$files/shot.png"

until_ok 5000 island_is '.surface == null'
open_chat

wtype -- "read this"
click_at chat-attach
check "a click on the paperclip opens the island's file picker over the chat ($(island | jq -c '{surface, takeover}'))" until_ok 4000 island_is '.takeover == "picker" and .surface == "chat"'
until_ok 4000 pk_is '.open and .settled and .keyboard and .listed'
wtype -M ctrl l -m ctrl
until_ok 2000 pk_is '.pathMode'
wtype "$files/one/" -k Return
until_ok 3000 pk_is --arg f "$files/one" '.folder == $f and .listed'
wtype -k Return
until_ok 3000 pk_is '.open == false'
until_ok 3000 chat_is '.keyboard and .settled'
check "picking notes.txt adds its chip, notes.txt at 2 KiB ($(chat | jq -c .attachments))" until_ok 3000 chat_is '.attachments == [{name: "notes.txt", size: 2048, kind: "text"}]'
check "the Enter that picked it sends nothing and keeps the typed text ($(chat | jq -c .input))" eval 'chat_is ".input == \"read this\"" && [ "$(lines)" -eq 0 ]'
wtype -k Return
check "the request carries the file's text ($(tail -1 "$requests" 2>/dev/null | jq -c '.messages[-1].content | tostring | .[0:60]'))" until_ok 3000 sent '.[-1].messages[-1].content | contains("MARKER-NOTES")'
check "the chip is gone once sent ($(chat | jq -c .attachments))" chat_is '.attachments == []'
until_ok 10000 chat_is '.streaming == false'

wl-copy -t image/png <"$files/shot.png"
wtype -M ctrl v -m ctrl
check "Ctrl+V of an image adds its chip ($(chat | jq -c .attachments))" until_ok 3000 chat_is '.attachments | length == 1 and .[0].kind == "image" and .[0].name == "pasted.png"'
check "the pill names the vision model ($(chat | jq -c .pill))" chat_is '.pill == "vision · amd/DeepSeek-V4-Flash-Vision-Exp"'
say "what is this"
check "the image turn asks the vision model with the image as a data URL ($(tail -1 "$requests" | jq -c '{model, parts: [.messages[-1].content[]?.type]}'))" until_ok 3000 sent '.[-1].model == "amd/DeepSeek-V4-Flash-Vision-Exp" and any(.[-1].messages[-1].content[] | select(.type == "image_url"); .image_url.url | startswith("data:image/png;base64,"))'
until_ok 10000 chat_is '.streaming == false'
say "and now"
check "the next turn goes back to the alias ($(tail -1 "$requests" | jq -c .model))" until_ok 3000 sent '.[-1].model == "chat" and .[-1].messages[-1].content == "and now"'
check "and carries no image from the turn before" sent '[.[-1].messages[] | .content | arrays | .[] | select(.type == "image_url")] == []'
until_ok 10000 chat_is '.streaming == false'

before=$(lines)
attach "$files/two"
check "a 600 KiB text file is refused with one line naming 512 KiB ($(chat | jq -c .refusal))" until_ok 3000 chat_is '(.refusal | contains("512 KiB")) and (.refusal | contains("\n") | not) and .attachments == []'
attach "$files/three"
check "a 6 MiB image is refused with one line naming 5 MiB ($(chat | jq -c .refusal))" until_ok 3000 chat_is '(.refusal | contains("5 MiB")) and .attachments == []'
sleep 1
check "a refusal sends nothing ($before then $(lines) requests)" test "$(lines)" -eq "$before"

# A new chat, so no earlier turn's notes.txt is in the request either.
wtype -M ctrl n -m ctrl
until_ok 2000 chat_is '.conversation == null'
attach "$files/one"
check "notes.txt is attached again ($(chat | jq -c .attachments))" until_ok 3000 chat_is '.attachments | length == 1'
click_at chat-unattach:0
check "a click on the chip's remove drops it ($(chat | jq -c .attachments))" until_ok 2000 chat_is '.attachments == []'
attach "$files/one"
until_ok 3000 chat_is '.attachments | length == 1'
wtype -k BackSpace
check "Backspace in the empty field drops the chip too ($(chat | jq -c .attachments))" until_ok 2000 chat_is '.attachments == []'
say "plain"
check "the request carries no trace of it ($(tail -1 "$requests" | jq -c '.messages[-1]'))" until_ok 3000 sent '(.[-1].messages[-1] == {role: "user", content: "plain"}) and (.[-1] | tostring | contains("MARKER-NOTES") | not)'
exit "$fails"
}
