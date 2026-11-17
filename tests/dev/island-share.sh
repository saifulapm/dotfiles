#!/usr/bin/env bash
# While a screen is shared the island shows no notification, so a share never carries one; each still reaches the notification centre, and once the share ends a new one shows again (61SHXHG7).
{
export DOTS_DEV_FAKE_CASTS=1
source "$(dirname "$0")/lib.sh"

island() { timeout 0.5 qs ipc call island state 2>/dev/null; }
island_is() { island | jq -e "$@" >/dev/null 2>&1; }
notifs_has() { timeout 0.5 qs ipc call notifs state 2>/dev/null | jq -e --arg s "$1" '.summaries | index($s) != null' >/dev/null 2>&1; }
cast() { fake_event "{\"CastStartedOrChanged\":{\"cast\":{\"stream_id\":$1,\"session_id\":$2,\"kind\":\"PipeWire\",\"target\":{\"Output\":{\"name\":\"winit\"}},\"is_dynamic_target\":false,\"is_active\":true,\"pid\":null,\"pw_node_id\":null}}}" >/dev/null; }
uncast() { fake_event "{\"CastStopped\":{\"stream_id\":$1}}" >/dev/null; }

until_ok 5000 shell_status >/dev/null
until_ok 3000 island_is '.mode == "rest"'

cast 7 1
until_ok 3000 island_is '.mode == "sharing"'
check "a screen share shows LIVE in the island ($(island | jq -c '{mode, text}'))" island_is '.mode == "sharing"'
notify-send "secret plans"
until_ok 3000 notifs_has "secret plans"
sleep 0.5
check "a notification sent during the share reaches the centre's history" notifs_has "secret plans"
check "but the island never shows it ($(island | jq -c '{mode, text}'))" island_is '.mode == "sharing" and (.text | test("secret") | not)'
notify-send -u critical "urgent secret"
until_ok 3000 notifs_has "urgent secret"
sleep 0.5
check "nor a critical one ($(island | jq -c '{mode, text}'))" island_is '(.text | test("secret") | not)'

uncast 7
until_ok 3000 island_is '.mode != "sharing"'
timeout 0.5 qs ipc call notifs clear
until_ok 8000 island_is '.mode == "rest"'
notify-send "after the share"
until_ok 3000 island_is '.mode == "notification"'
check "once the share ends a new notification shows again ($(island | jq -c '{mode, text}'))" island_is '.mode == "notification" and (.text | test("after the share"))'
exit "$fails"
}
