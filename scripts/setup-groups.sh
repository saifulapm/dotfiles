#!/bin/bash
# Add user to required groups for voxtype, screen recording, etc.

set -e

GROUPS_TO_ADD=(input video render audio)

echo "Adding user to required groups..."

for group in "${GROUPS_TO_ADD[@]}"; do
    if getent group "$group" >/dev/null 2>&1; then
        if ! groups | grep -qw "$group"; then
            sudo usermod -aG "$group" "$USER"
            echo "  Added to: $group"
        else
            echo "  Already in: $group"
        fi
    else
        echo "  Group not found: $group (skipping)"
    fi
done

echo ""
echo "Done! Log out and back in for changes to take effect."
