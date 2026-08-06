#!/bin/bash
# Thin wrapper: feeds statusline stdin JSON to the Python renderer.
exec python3 "$HOME/.claude/statusline.py"
