#!/bin/bash

# Install try-cli from source
# https://github.com/tobi/try-cli

set -e

UPDATE_MODE=false
[[ "$1" == "--update" ]] && UPDATE_MODE=true

if command -v try &>/dev/null && [[ "$UPDATE_MODE" == "false" ]]; then
    echo "try already installed"
    exit 0
fi

TMP_DIR=$(mktemp -d)
cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT

cd "$TMP_DIR"

git clone --quiet https://github.com/tobi/try-cli.git
cd try-cli
make
sudo make install
