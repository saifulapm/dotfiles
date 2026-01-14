#!/bin/bash
# Screen recording indicator for waybar

if pgrep -f "^gpu-screen-recorder" >/dev/null; then
    echo '{"text": "󰻂", "tooltip": "Stop recording", "class": "active"}'
else
    echo '{"text": ""}'
fi
