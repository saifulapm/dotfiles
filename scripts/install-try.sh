#!/bin/bash

# Install try-cli from source
# https://github.com/tobi/try-cli

set -e

TMP_DIR=$(mktemp -d)
cd "$TMP_DIR"

git clone --quiet https://github.com/tobi/try-cli.git
cd try-cli
make
sudo make install

cd /
rm -rf "$TMP_DIR"
